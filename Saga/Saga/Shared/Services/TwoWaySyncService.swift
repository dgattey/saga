//
//  TwoWaySyncService.swift
//  Saga
//
//  Orchestrates two-way sync between CoreData and Contentful.
//
//  Workflow (per Contentful best practices):
//  1. User edits CoreData → isDirty = true
//  2. Sync down first via ContentfulPersistence (delta sync)
//  3. For each dirty object, fetch current sys.version from CMA
//  4. Resolve conflicts (latest-wins via updatedAt)
//  5. Push changes via CMA
//  6. Explicitly publish entries
//  7. Mark isDirty = false, update contentfulVersion
//

import Combine
import Contentful
import ContentfulPersistence
import CoreData
import Foundation

/// Configuration for two-way sync behavior
struct TwoWaySyncConfig {
  /// Minimum interval between sync operations (seconds)
  var syncDebounceInterval: TimeInterval = 2.0

  /// Whether to auto-publish entries after creating/updating
  var autoPublish: Bool = true

  /// Conflict resolution strategy
  var conflictResolution: ConflictResolution = .latestWins

  enum ConflictResolution {
    case latestWins  // Compare updatedAt timestamps, skip if server is newer
    case localWins  // Always push local changes (overwrites server)
  }
}

/// Tracks whether a ContentfulPersistence pull is in progress.
/// Models should check this in willSave() to avoid marking objects dirty
/// when changes originate from the server rather than local user edits.
enum SyncState {
  /// Thread-safe flag indicating a pull operation is in progress
  private static let lock = NSLock()
  private static var _isPulling = false

  static var isPulling: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isPulling
  }

  static func setIsPulling(_ value: Bool) {
    lock.lock()
    defer { lock.unlock() }
    _isPulling = value
  }
}

/// Service that coordinates bidirectional sync between CoreData and Contentful
///
/// **IMPORTANT**: This service requires a Content Management API token.
/// Configure `CONTENTFUL_MANAGEMENT_TOKEN` in Config.xcconfig.
final class TwoWaySyncService: ObservableObject {

  // MARK: - Published State

  @Published private(set) var isSyncing = false
  @Published private(set) var lastSyncDate: Date?
  @Published private(set) var pendingPushCount: Int = 0
  @Published private(set) var lastError: Error?

  // MARK: - Dependencies

  private let container: NSPersistentContainer
  private let syncManager: SynchronizationManager
  private let managementService: ContentfulManagementService
  private let config: TwoWaySyncConfig

  // MARK: - Private State

  private var cancellables = Set<AnyCancellable>()
  private var syncDebounceTask: Task<Void, Never>?

  // MARK: - Initialization

  /// Creates a two-way sync service.
  /// - Throws: `ContentfulManagementError.missingManagementToken` if not configured
  init(
    container: NSPersistentContainer,
    syncManager: SynchronizationManager,
    config: TwoWaySyncConfig = TwoWaySyncConfig()
  ) throws {
    self.container = container
    self.syncManager = syncManager
    self.config = config

    // LOUD FAILURE: Two-way sync requires management token
    self.managementService = try ContentfulManagementService()

    LoggerService.log(
      "Two-way sync service initialized",
      level: .notice,
      surface: .sync
    )

    setupChangeObserver()
  }

  // MARK: - Public API

  /// Performs a full sync cycle:
  /// 1. Pull from Contentful (sync down)
  /// 2. Push dirty local changes (sync up)
  func sync() async throws {
    // Atomically check and set isSyncing to prevent race conditions
    let shouldProceed = await MainActor.run {
      if isSyncing {
        return false
      }
      isSyncing = true
      return true
    }

    guard shouldProceed else {
      LoggerService.log("Sync already in progress, skipping", level: .debug, surface: .sync)
      return
    }

    do {
      // Step 1: ALWAYS sync down first to get latest state
      try await pull()

      // Step 2: Push any dirty local changes
      try await pushDirtyObjects()

      await finishSync()
    } catch {
      await finishSync()
      throw error
    }
  }

  /// Resets sync state after a sync operation completes (success or failure)
  private func finishSync() async {
    await MainActor.run {
      isSyncing = false
      lastSyncDate = Date()
      pendingPushCount = countDirtyObjects()
    }
  }

  /// Resets all local data and re-syncs from Contentful
  func resetAndSync() async throws {
    // Delete all local data
    let entityNames = container.managedObjectModel.entities.compactMap { $0.name }
    for entityName in entityNames {
      let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
      let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      deleteRequest.resultType = .resultTypeObjectIDs

      try await container.performBackgroundTask { context in
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        let changes: [AnyHashable: Any] = [
          NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []
        ]
        NSManagedObjectContext.mergeChanges(
          fromRemoteContextSave: changes,
          into: [self.container.viewContext]
        )
      }
    }

    LoggerService.log("Cleared all local data", level: .notice, surface: .sync)

    // Re-sync from Contentful
    try await sync()
  }

  // MARK: - Pull (Contentful → CoreData)

  private func pull() async throws {
    LoggerService.log("Pulling from Contentful...", level: .debug, surface: .sync)

    // Set flag to prevent willSave() from marking objects dirty during pull
    SyncState.setIsPulling(true)
    defer { SyncState.setIsPulling(false) }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      syncManager.sync { result in
        switch result {
        case .success:
          LoggerService.log("Pull completed", level: .debug, surface: .sync)
          continuation.resume()
        case .failure(let error):
          LoggerService.log("Pull failed", error: error, surface: .sync)
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: - Push (CoreData → Contentful)

  private func pushDirtyObjects() async throws {
    let dirtyBooks = try await fetchDirtyBooks()
    let dirtyAssets = try await fetchDirtyAssets()

    let totalDirty = dirtyBooks.count + dirtyAssets.count
    guard totalDirty > 0 else {
      LoggerService.log("No dirty objects to push", level: .debug, surface: .sync)
      return
    }

    LoggerService.log(
      "Pushing \(totalDirty) dirty objects (\(dirtyBooks.count) books, \(dirtyAssets.count) assets)",
      level: .notice,
      surface: .sync
    )

    // Push assets first (books may reference them)
    for assetID in dirtyAssets {
      try await pushAsset(objectID: assetID)
    }

    // Push books
    for bookID in dirtyBooks {
      try await pushBook(objectID: bookID)
    }
  }

  private func fetchDirtyBooks() async throws -> [NSManagedObjectID] {
    try await container.viewContext.perform {
      let request = NSFetchRequest<Book>(entityName: "Book")
      request.predicate = NSPredicate(format: "isDirty == YES")
      let books = try self.container.viewContext.fetch(request)
      return books.map { $0.objectID }
    }
  }

  private func fetchDirtyAssets() async throws -> [NSManagedObjectID] {
    try await container.viewContext.perform {
      let request = NSFetchRequest<Asset>(entityName: "Asset")
      request.predicate = NSPredicate(format: "isDirty == YES")
      let assets = try self.container.viewContext.fetch(request)
      return assets.map { $0.objectID }
    }
  }

  // MARK: - Push Book

  private func pushBook(objectID: NSManagedObjectID) async throws {
    let bookData = try await fetchBookData(objectID: objectID)

    // Step 1: Fetch current server state to get sys.version
    let serverState: (version: Int, updatedAt: Date?)?
    do {
      serverState = try await managementService.fetchEntryMetadata(id: bookData.id)
    } catch ContentfulManagementError.entryNotFound {
      serverState = nil  // New entry, will create
    }

    // Step 2: Conflict resolution
    if let serverState = serverState,
      config.conflictResolution == .latestWins,
      let serverUpdatedAt = serverState.updatedAt,
      let localUpdatedAt = bookData.updatedAt,
      serverUpdatedAt > localUpdatedAt
    {
      LoggerService.log(
        "Skipping book \(bookData.id): server is newer (server: \(serverUpdatedAt), local: \(localUpdatedAt))",
        level: .notice,
        surface: .sync
      )
      // Mark as clean since server has newer data
      await markBookClean(objectID: objectID, version: serverState.version)
      return
    }

    // Step 3: Build fields and push
    let fields = buildBookFields(from: bookData)

    let newVersion: Int
    if let serverState = serverState {
      // Update existing entry
      newVersion = try await managementService.updateEntry(
        id: bookData.id,
        version: serverState.version,
        fields: fields
      )
      LoggerService.log("Updated book \(bookData.id) to version \(newVersion)", level: .debug, surface: .sync)
    } else {
      // Create new entry
      let (_, version) = try await managementService.createEntry(
        contentTypeId: Book.contentTypeId,
        id: bookData.id,
        fields: fields
      )
      newVersion = version
      LoggerService.log("Created book \(bookData.id) at version \(newVersion)", level: .debug, surface: .sync)
    }

    // Step 4: Publish
    if config.autoPublish {
      try await managementService.publishEntry(id: bookData.id, version: newVersion)
      LoggerService.log("Published book \(bookData.id)", level: .debug, surface: .sync)
    }

    // Step 5: Mark clean and update version
    await markBookClean(objectID: objectID, version: newVersion + 1)  // Version increments on publish
  }

  private struct BookData {
    let id: String
    let title: String?
    let author: String?
    let isbn: NSNumber?
    let rating: NSNumber?
    let readDateStarted: Date?
    let readDateFinished: Date?
    let reviewDescription: RichTextDocument?
    let coverImageId: String?
    let updatedAt: Date?
  }

  private func fetchBookData(objectID: NSManagedObjectID) async throws -> BookData {
    try await container.viewContext.perform {
      guard let book = try? self.container.viewContext.existingObject(with: objectID) as? Book
      else {
        throw ContentfulManagementError.entryNotFound(id: objectID.uriRepresentation().absoluteString)
      }

      return BookData(
        id: book.id,
        title: book.title,
        author: book.author,
        isbn: book.isbn,
        rating: book.rating,
        readDateStarted: book.readDateStarted,
        readDateFinished: book.readDateFinished,
        reviewDescription: book.reviewDescription,
        coverImageId: book.coverImage?.id,
        updatedAt: book.updatedAt
      )
    }
  }

  private func buildBookFields(from data: BookData) -> [String: Any] {
    var fields: [String: Any] = [:]

    if let title = data.title {
      fields["title"] = ["en-US": title]
    }
    if let author = data.author {
      fields["author"] = ["en-US": author]
    }
    if let isbn = data.isbn {
      fields["isbn"] = ["en-US": isbn.intValue]
    }
    if let rating = data.rating {
      fields["rating"] = ["en-US": rating.intValue]
    }
    if let readDateStarted = data.readDateStarted {
      fields["readDateStarted"] = ["en-US": ISO8601DateFormatter().string(from: readDateStarted)]
    }
    if let readDateFinished = data.readDateFinished {
      fields["readDateFinished"] = ["en-US": ISO8601DateFormatter().string(from: readDateFinished)]
    }
    if let coverImageId = data.coverImageId {
      fields["coverImage"] = [
        "en-US": [
          "sys": [
            "type": "Link",
            "linkType": "Asset",
            "id": coverImageId,
          ]
        ]
      ]
    }
    if let reviewDescription = data.reviewDescription {
      // Serialize RichTextDocument to JSON for Contentful's rich text field format
      if let jsonData = try? JSONEncoder().encode(reviewDescription),
        let jsonObject = try? JSONSerialization.jsonObject(with: jsonData)
      {
        fields["reviewDescription"] = ["en-US": jsonObject]
      }
    }

    return fields
  }

  private func markBookClean(objectID: NSManagedObjectID, version: Int) async {
    await container.viewContext.perform {
      guard let book = try? self.container.viewContext.existingObject(with: objectID) as? Book
      else { return }
      book.isDirty = false
      book.contentfulVersion = version
      try? self.container.viewContext.save()
    }
  }

  // MARK: - Push Asset

  private func pushAsset(objectID: NSManagedObjectID) async throws {
    let assetData = try await fetchAssetData(objectID: objectID)

    guard let urlString = assetData.urlString, let url = URL(string: urlString) else {
      throw ContentfulManagementError.assetUploadFailed(reason: "Asset has no URL")
    }

    // Check if asset already exists on server (use asset endpoint, not entry endpoint)
    let serverState: (version: Int, updatedAt: Date?)?
    do {
      serverState = try await managementService.fetchAssetMetadata(id: assetData.id)
    } catch ContentfulManagementError.entryNotFound {
      serverState = nil
    }

    // Skip if server is newer (for existing assets)
    if let serverState = serverState,
      config.conflictResolution == .latestWins,
      let serverUpdatedAt = serverState.updatedAt,
      let localUpdatedAt = assetData.updatedAt,
      serverUpdatedAt > localUpdatedAt
    {
      LoggerService.log(
        "Skipping asset \(assetData.id): server is newer",
        level: .notice,
        surface: .sync
      )
      await markAssetClean(objectID: objectID, version: serverState.version)
      return
    }

    // For new assets, download and upload
    if serverState == nil {
      let (imageData, _) = try await URLSession.shared.data(from: url)

      let fileName = assetData.fileName ?? "\(assetData.id).jpg"
      let contentType = assetData.fileType ?? "image/jpeg"

      let (_, uploadedURL, finalVersion) = try await managementService.uploadAsset(
        id: assetData.id,
        title: assetData.title,
        description: assetData.assetDescription,
        fileData: imageData,
        fileName: fileName,
        contentType: contentType
      )

      // Update local URL and mark clean with actual version
      await updateAssetAndMarkClean(objectID: objectID, url: uploadedURL, version: finalVersion)
      LoggerService.log("Uploaded asset \(assetData.id)", level: .debug, surface: .sync)
    } else {
      // Existing asset - just update metadata if needed
      let newVersion = try await managementService.updateAsset(
        id: assetData.id,
        version: serverState!.version,
        title: assetData.title,
        description: assetData.assetDescription
      )
      await markAssetClean(objectID: objectID, version: newVersion)
    }
  }

  private struct AssetData {
    let id: String
    let title: String?
    let assetDescription: String?
    let urlString: String?
    let fileName: String?
    let fileType: String?
    let updatedAt: Date?
  }

  private func fetchAssetData(objectID: NSManagedObjectID) async throws -> AssetData {
    try await container.viewContext.perform {
      guard let asset = try? self.container.viewContext.existingObject(with: objectID) as? Asset
      else {
        throw ContentfulManagementError.entryNotFound(id: objectID.uriRepresentation().absoluteString)
      }

      return AssetData(
        id: asset.id,
        title: asset.title,
        assetDescription: asset.assetDescription,
        urlString: asset.urlString,
        fileName: asset.fileName,
        fileType: asset.fileType,
        updatedAt: asset.updatedAt
      )
    }
  }

  private func markAssetClean(objectID: NSManagedObjectID, version: Int) async {
    await container.viewContext.perform {
      guard let asset = try? self.container.viewContext.existingObject(with: objectID) as? Asset
      else { return }
      asset.isDirty = false
      asset.contentfulVersion = version
      try? self.container.viewContext.save()
    }
  }

  private func updateAssetAndMarkClean(objectID: NSManagedObjectID, url: String, version: Int) async
  {
    await container.viewContext.perform {
      guard let asset = try? self.container.viewContext.existingObject(with: objectID) as? Asset
      else { return }

      // Set flag to prevent willSave() from treating URL update as user edit
      // (urlString is not in syncMetadataKeys, so it would re-mark isDirty = true)
      SyncState.setIsPulling(true)
      defer { SyncState.setIsPulling(false) }

      asset.urlString = url
      asset.isDirty = false
      asset.contentfulVersion = version
      try? self.container.viewContext.save()
    }
  }

  // MARK: - Change Observer

  private func setupChangeObserver() {
    // Observe CoreData saves to track dirty count
    NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: container.viewContext)
      .sink { [weak self] _ in
        self?.scheduleSyncIfNeeded()
      }
      .store(in: &cancellables)
  }

  private func scheduleSyncIfNeeded() {
    let dirtyCount = countDirtyObjects()
    Task { @MainActor in
      pendingPushCount = dirtyCount
    }

    guard dirtyCount > 0 else { return }

    // Debounce auto-sync
    syncDebounceTask?.cancel()
    syncDebounceTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(config.syncDebounceInterval * 1_000_000_000))
      guard !Task.isCancelled else { return }

      do {
        try await sync()
      } catch {
        LoggerService.log("Auto-sync failed", error: error, surface: .sync)
        await MainActor.run { lastError = error }
      }
    }
  }

  private func countDirtyObjects() -> Int {
    var count = 0
    container.viewContext.performAndWait {
      let bookRequest = NSFetchRequest<Book>(entityName: "Book")
      bookRequest.predicate = NSPredicate(format: "isDirty == YES")
      count += (try? container.viewContext.count(for: bookRequest)) ?? 0

      let assetRequest = NSFetchRequest<Asset>(entityName: "Asset")
      assetRequest.predicate = NSPredicate(format: "isDirty == YES")
      count += (try? container.viewContext.count(for: assetRequest)) ?? 0
    }
    return count
  }
}

// MARK: - Version Tracking Protocol

/// Protocol for tracking Contentful version numbers on local objects
protocol ContentfulVersionTracking {
  var contentfulVersion: Int { get set }
}

/// Protocol for objects that can be synced to Contentful
protocol ContentfulSyncable {
  /// The Contentful entry/asset ID
  var id: String { get }
  /// When the object was last updated locally
  var updatedAt: Date? { get }
  /// Whether this object has local changes not yet synced
  var isDirty: Bool { get set }
}

// MARK: - Shared Dirty Tracking

/// Properties that should NOT trigger isDirty (sync metadata)
private let contentfulSyncMetadataKeys: Set<String> = [
  "isDirty", "contentfulVersion", "updatedAt", "createdAt", "localeCode"
]

extension ContentfulSyncable where Self: NSManagedObject {
  /// Handles dirty tracking in willSave(). Call this from your willSave() override.
  func handleDirtyTracking() {
    // Skip if being deleted or during a sync pull operation
    // (changes from server should not mark objects as dirty)
    guard !isDeleted, !SyncState.isPulling else { return }

    // Check if any non-metadata properties changed
    let changedKeys = Set(changedValues().keys)
    let contentKeys = changedKeys.subtracting(contentfulSyncMetadataKeys)

    if !contentKeys.isEmpty {
      // Use primitiveValue to avoid triggering another willSave
      // Always update updatedAt for accurate conflict resolution (latest-wins)
      setPrimitiveValue(Date(), forKey: "updatedAt")
      // Only set isDirty if not already dirty (avoid redundant write)
      if !isDirty {
        setPrimitiveValue(true, forKey: "isDirty")
      }
    }
  }
}
