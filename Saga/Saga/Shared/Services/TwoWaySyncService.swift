//
//  TwoWaySyncService.swift
//  Saga
//
//  Orchestrates two-way sync between CoreData and Contentful.
//  - Pull: Uses ContentfulPersistence's SynchronizationManager (existing)
//  - Push: Uses ContentfulManagementService to write changes back
//
//  Conflict resolution: Latest-wins based on updatedAt timestamps
//

import Combine
import Contentful
import ContentfulPersistence
import CoreData
import Foundation

/// Configuration for two-way sync behavior
struct TwoWaySyncConfig {
  /// Whether to automatically push local changes
  var autoPushEnabled: Bool = true

  /// Minimum interval between push operations (seconds)
  var pushDebounceInterval: TimeInterval = 2.0

  /// Whether to auto-publish entries after creating/updating
  var autoPublish: Bool = true

  /// Conflict resolution strategy
  var conflictResolution: ConflictResolution = .latestWins

  enum ConflictResolution {
    case latestWins  // Compare updatedAt timestamps
    case localWins  // Always prefer local changes
    case serverWins  // Always prefer server changes
  }
}

/// Service that coordinates bidirectional sync between CoreData and Contentful
final class TwoWaySyncService: ObservableObject {

  // MARK: - Published State

  @Published private(set) var isPulling = false
  @Published private(set) var isPushing = false
  @Published private(set) var lastPullDate: Date?
  @Published private(set) var lastPushDate: Date?
  @Published private(set) var pendingPushCount: Int = 0
  @Published private(set) var lastError: Error?

  var isSyncing: Bool { isPulling || isPushing }

  // MARK: - Dependencies

  private let container: NSPersistentContainer
  private let syncManager: SynchronizationManager
  private let changeObserver: CoreDataChangeObserver
  private var managementService: ContentfulManagementService?
  private let config: TwoWaySyncConfig

  // MARK: - Private State

  private var cancellables = Set<AnyCancellable>()
  private var pushTask: Task<Void, Never>?
  private var pushDebounceTask: Task<Void, Never>?

  // MARK: - Initialization

  init(
    container: NSPersistentContainer,
    syncManager: SynchronizationManager,
    config: TwoWaySyncConfig = TwoWaySyncConfig()
  ) {
    self.container = container
    self.syncManager = syncManager
    self.config = config
    self.changeObserver = CoreDataChangeObserver(context: container.viewContext)

    // Initialize management service if token is available
    if BundleKey.hasManagementToken {
      do {
        self.managementService = try ContentfulManagementService()
        LoggerService.log(
          "Two-way sync enabled (management token configured)",
          level: .notice,
          surface: .sync
        )
      } catch {
        LoggerService.log(
          "Two-way sync disabled: \(error.localizedDescription)",
          level: .warning,
          surface: .sync
        )
      }
    } else {
      LoggerService.log(
        "Two-way sync disabled (no management token)",
        level: .notice,
        surface: .sync
      )
    }

    setupObservers()
  }

  // MARK: - Public API: Pull (Contentful → CoreData)

  /// Pulls changes from Contentful to CoreData
  /// Uses ContentfulPersistence's delta sync via sync tokens
  func pull() async throws {
    guard !isPulling else {
      LoggerService.log("Pull already in progress, skipping", level: .debug, surface: .sync)
      return
    }

    await MainActor.run { isPulling = true }

    // Pause change observer to avoid triggering push for incoming changes
    changeObserver.pause()

    defer {
      Task { @MainActor in
        isPulling = false
        lastPullDate = Date()
      }
      changeObserver.resume()
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      syncManager.sync { result in
        switch result {
        case .success:
          LoggerService.log("Pull completed successfully", level: .debug, surface: .sync)
          continuation.resume()
        case .failure(let error):
          LoggerService.log("Pull failed", error: error, surface: .sync)
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: - Public API: Push (CoreData → Contentful)

  /// Pushes local changes to Contentful
  /// Only available if management token is configured
  func push() async throws {
    guard let managementService = managementService else {
      throw ContentfulManagementError.missingManagementToken
    }

    guard !isPushing else {
      LoggerService.log("Push already in progress, skipping", level: .debug, surface: .sync)
      return
    }

    let changes = changeObserver.pendingChanges
    guard !changes.isEmpty else {
      LoggerService.log("No pending changes to push", level: .debug, surface: .sync)
      return
    }

    await MainActor.run {
      isPushing = true
      pendingPushCount = changes.count
    }

    defer {
      Task { @MainActor in
        isPushing = false
        lastPushDate = Date()
        pendingPushCount = changeObserver.pendingChanges.count
      }
    }

    LoggerService.log("Pushing \(changes.count) changes to Contentful", level: .notice, surface: .sync)

    var successfulChanges: [LocalChange] = []
    var errors: [Error] = []

    for change in changes {
      do {
        try await pushChange(change, using: managementService)
        successfulChanges.append(change)
      } catch {
        LoggerService.log(
          "Failed to push change for \(change.entityName) \(change.contentfulId)",
          error: error,
          surface: .sync
        )
        errors.append(error)
      }
    }

    // Remove successful changes from queue
    changeObserver.removeChanges(successfulChanges)

    if !errors.isEmpty {
      LoggerService.log(
        "Push completed with \(errors.count) errors",
        level: .warning,
        surface: .sync
      )
      await MainActor.run { lastError = errors.first }
    } else {
      LoggerService.log(
        "Push completed successfully (\(successfulChanges.count) changes)",
        level: .notice,
        surface: .sync
      )
    }
  }

  /// Performs a full sync: pull then push
  func sync() async throws {
    try await pull()

    if managementService != nil {
      try await push()
    }
  }

  /// Resets all local data and re-syncs from Contentful
  func resetAndSync() async throws {
    // Clear pending changes since we're resetting
    changeObserver.clearPendingChanges()

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

    // Re-sync from Contentful
    try await pull()
  }

  // MARK: - Push Individual Changes

  private func pushChange(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    switch change.changeType {
    case .insert:
      try await pushInsert(change, using: service)
    case .update:
      try await pushUpdate(change, using: service)
    case .delete:
      try await pushDelete(change, using: service)
    }
  }

  private func pushInsert(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    switch change.entityName {
    case "Book":
      try await pushBookInsert(change, using: service)
    case "Asset":
      try await pushAssetInsert(change, using: service)
    default:
      LoggerService.log(
        "Unknown entity type for insert: \(change.entityName)",
        level: .warning,
        surface: .sync
      )
    }
  }

  private func pushUpdate(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    switch change.entityName {
    case "Book":
      try await pushBookUpdate(change, using: service)
    case "Asset":
      // Asset updates are handled differently - typically metadata only
      LoggerService.log("Asset update skipped (metadata only)", level: .debug, surface: .sync)
    default:
      LoggerService.log(
        "Unknown entity type for update: \(change.entityName)",
        level: .warning,
        surface: .sync
      )
    }
  }

  private func pushDelete(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    switch change.entityName {
    case "Book":
      try await service.deleteEntry(id: change.contentfulId)
    case "Asset":
      try await service.deleteAsset(id: change.contentfulId)
    default:
      LoggerService.log(
        "Unknown entity type for delete: \(change.entityName)",
        level: .warning,
        surface: .sync
      )
    }
  }

  // MARK: - Book Sync

  private func pushBookInsert(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    let bookData = try await fetchBookData(objectID: change.objectID)

    let fields = buildBookFields(from: bookData)

    let (entryId, version) = try await service.createEntry(
      contentTypeId: Book.contentTypeId,
      id: change.contentfulId,
      fields: fields
    )

    if config.autoPublish {
      try await service.publishEntry(id: entryId, version: version)
    }

    // Update local object with Contentful version
    await updateLocalBookVersion(objectID: change.objectID, version: version)
  }

  private func pushBookUpdate(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    let bookData = try await fetchBookData(objectID: change.objectID)

    // Check for conflicts using latest-wins
    if config.conflictResolution == .latestWins {
      do {
        let serverMeta = try await service.fetchEntryMetadata(id: change.contentfulId)
        if let serverUpdatedAt = serverMeta.updatedAt,
          let localUpdatedAt = bookData.updatedAt,
          serverUpdatedAt > localUpdatedAt
        {
          LoggerService.log(
            "Server version is newer, skipping push for \(change.contentfulId)",
            level: .debug,
            surface: .sync
          )
          return
        }
      } catch ContentfulManagementError.entryNotFound {
        // Entry doesn't exist on server, treat as insert
        try await pushBookInsert(change, using: service)
        return
      }
    }

    let fields = buildBookFields(from: bookData)

    do {
      let newVersion = try await service.updateEntry(
        id: change.contentfulId,
        version: bookData.contentfulVersion,
        fields: fields
      )

      if config.autoPublish {
        try await service.publishEntry(id: change.contentfulId, version: newVersion)
      }

      await updateLocalBookVersion(objectID: change.objectID, version: newVersion)
    } catch ContentfulManagementError.versionConflict(let serverVersion) {
      // Retry with server version (latest-wins means we overwrite)
      if config.conflictResolution == .latestWins || config.conflictResolution == .localWins {
        let newVersion = try await service.updateEntry(
          id: change.contentfulId,
          version: serverVersion,
          fields: fields
        )

        if config.autoPublish {
          try await service.publishEntry(id: change.contentfulId, version: newVersion)
        }

        await updateLocalBookVersion(objectID: change.objectID, version: newVersion)
      } else {
        throw ContentfulManagementError.versionConflict(serverVersion: serverVersion)
      }
    }
  }

  private struct BookData {
    let title: String?
    let author: String?
    let isbn: NSNumber?
    let rating: NSNumber?
    let readDateStarted: Date?
    let readDateFinished: Date?
    let reviewDescription: RichTextDocument?
    let coverImageId: String?
    let updatedAt: Date?
    let contentfulVersion: Int
  }

  private func fetchBookData(objectID: NSManagedObjectID) async throws -> BookData {
    try await container.viewContext.perform {
      guard let book = try? self.container.viewContext.existingObject(with: objectID) as? Book
      else {
        throw ContentfulManagementError.entryNotFound(id: objectID.uriRepresentation().absoluteString)
      }

      return BookData(
        title: book.title,
        author: book.author,
        isbn: book.isbn,
        rating: book.rating,
        readDateStarted: book.readDateStarted,
        readDateFinished: book.readDateFinished,
        reviewDescription: book.reviewDescription,
        coverImageId: book.coverImage?.id,
        updatedAt: book.updatedAt,
        contentfulVersion: (book as? ContentfulVersionTracking)?.contentfulVersion ?? 1
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
    // Note: Rich text requires special handling - simplified for now
    // Full implementation would convert RichTextDocument back to Contentful format

    return fields
  }

  private func updateLocalBookVersion(objectID: NSManagedObjectID, version: Int) async {
    await container.viewContext.perform {
      guard let book = try? self.container.viewContext.existingObject(with: objectID) as? Book
      else { return }
      if var versionTracking = book as? ContentfulVersionTracking {
        versionTracking.contentfulVersion = version
      }
      book.updatedAt = Date()
      try? self.container.viewContext.save()
    }
  }

  // MARK: - Asset Sync

  private func pushAssetInsert(
    _ change: LocalChange,
    using service: ContentfulManagementService
  ) async throws {
    // For assets, we need the actual image data
    // This is more complex - typically assets are created from URLs or local files

    let assetData = try await fetchAssetData(objectID: change.objectID)

    // If we have a URL, we might need to download and re-upload
    // For now, log that this requires special handling
    LoggerService.log(
      "Asset insert requires image data - URL: \(assetData.urlString ?? "none")",
      level: .notice,
      surface: .sync
    )

    // If the asset has a URL from an external source, we can create it with that URL
    // Otherwise, we'd need the raw image data
    guard let urlString = assetData.urlString,
      let url = URL(string: urlString)
    else {
      throw ContentfulManagementError.assetUploadFailed(reason: "No URL available for asset")
    }

    // Download image data
    let (imageData, _) = try await URLSession.shared.data(from: url)

    let fileName = assetData.fileName ?? "\(change.contentfulId).jpg"
    let contentType = assetData.fileType ?? "image/jpeg"

    let (_, uploadedURL) = try await service.uploadAsset(
      id: change.contentfulId,
      title: assetData.title,
      description: assetData.assetDescription,
      fileData: imageData,
      fileName: fileName,
      contentType: contentType
    )

    // Update local asset with new URL
    await updateLocalAssetURL(objectID: change.objectID, url: uploadedURL)
  }

  private struct AssetData {
    let title: String?
    let assetDescription: String?
    let urlString: String?
    let fileName: String?
    let fileType: String?
  }

  private func fetchAssetData(objectID: NSManagedObjectID) async throws -> AssetData {
    try await container.viewContext.perform {
      guard let asset = try? self.container.viewContext.existingObject(with: objectID) as? Asset
      else {
        throw ContentfulManagementError.entryNotFound(id: objectID.uriRepresentation().absoluteString)
      }

      return AssetData(
        title: asset.title,
        assetDescription: asset.assetDescription,
        urlString: asset.urlString,
        fileName: asset.fileName,
        fileType: asset.fileType
      )
    }
  }

  private func updateLocalAssetURL(objectID: NSManagedObjectID, url: String) async {
    await container.viewContext.perform {
      guard let asset = try? self.container.viewContext.existingObject(with: objectID) as? Asset
      else { return }
      asset.urlString = url
      asset.updatedAt = Date()
      try? self.container.viewContext.save()
    }
  }

  // MARK: - Auto Push Setup

  private func setupObservers() {
    guard config.autoPushEnabled, managementService != nil else { return }

    // Listen for local changes
    NotificationCenter.default.publisher(for: .localChangesAvailable)
      .sink { [weak self] _ in
        self?.scheduleAutoPush()
      }
      .store(in: &cancellables)

    // Track pending change count
    changeObserver.$pendingChanges
      .map { $0.count }
      .receive(on: DispatchQueue.main)
      .assign(to: &$pendingPushCount)
  }

  private func scheduleAutoPush() {
    pushDebounceTask?.cancel()
    pushDebounceTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(config.pushDebounceInterval * 1_000_000_000))

      guard !Task.isCancelled else { return }

      do {
        try await push()
      } catch {
        LoggerService.log("Auto-push failed", error: error, surface: .sync)
      }
    }
  }
}

// MARK: - Version Tracking Protocol

/// Protocol for tracking Contentful version numbers on local objects
protocol ContentfulVersionTracking {
  var contentfulVersion: Int { get set }
}
