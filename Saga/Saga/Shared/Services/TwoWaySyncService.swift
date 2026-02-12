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
import CoreData
import Foundation

// MARK: - TwoWaySyncService

/// Service that coordinates bidirectional sync between CoreData and Contentful
///
/// **IMPORTANT**: This service requires a Content Management API token.
/// Configure `CONTENTFUL_MANAGEMENT_ACCESS_TOKEN` in Config.xcconfig.
final class TwoWaySyncService: ObservableObject {

  // MARK: - Published State

  @Published private(set) var isSyncing = false
  @Published private(set) var lastSyncDate: Date?
  @Published private(set) var pendingPushCount: Int = 0
  @Published private(set) var lastError: Error?
  @Published private(set) var skippedConflicts: [ConflictInfo] = []

  // MARK: - Dependencies

  private let container: NSPersistentContainer
  private let pullFunction: () async throws -> Void
  private let managementService: ContentfulManagementService
  private let pushableTypes: [any ContentfulPushable.Type]
  private let config: TwoWaySyncConfig

  // MARK: - Private State

  private var cancellables = Set<AnyCancellable>()
  private var syncDebounceTask: Task<Void, Never>?

  // MARK: - Initialization

  /// Creates a two-way sync service.
  /// - Parameters:
  ///   - container: The Core Data persistent container
  ///   - pull: Closure that fetches content from Contentful and writes it to Core Data
  ///   - pushableTypes: The entity types that can be pushed to Contentful
  ///   - config: Sync configuration (debounce, autoPublish, conflict resolution)
  /// - Throws: `ContentfulManagementError.missingManagementToken` if not configured
  init(
    container: NSPersistentContainer,
    pull: @escaping () async throws -> Void,
    pushableTypes: [any ContentfulPushable.Type],
    config: TwoWaySyncConfig = TwoWaySyncConfig()
  ) throws {
    self.container = container
    self.pullFunction = pull
    self.pushableTypes = pushableTypes
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

  deinit {
    // Cancel debounce task to prevent it from running after mode switch
    syncDebounceTask?.cancel()
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
      skippedConflicts = []  // Clear conflicts at start of sync
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
      try await pushAllDirtyObjects()

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
    try await pullFunction()
    LoggerService.log("Pull completed", level: .debug, surface: .sync)
  }

  // MARK: - Push (CoreData → Contentful)

  private func pushAllDirtyObjects() async throws {
    // Push assets first (entries may reference them)
    // Assets have special handling because new assets require file upload
    try await pushDirtyAssets()

    // Push all registered pushable types using the generic flow
    for type in pushableTypes {
      // Skip assets -- already handled above with special upload logic
      guard type.resourceType != .asset else { continue }
      try await pushDirtyObjects(ofType: type)
    }
  }

  // MARK: - Asset Push (Special Handling)

  /// Assets require special handling because new assets need file upload
  private func pushDirtyAssets() async throws {
    // Find all asset types in the registry
    let assetTypes = pushableTypes.filter { $0.resourceType == .asset }
    guard !assetTypes.isEmpty else { return }

    for assetType in assetTypes {
      let dirtyAssetIDs = try await fetchDirtyObjectIDs(entityName: assetType.entityName)

      guard !dirtyAssetIDs.isEmpty else { continue }

      LoggerService.log(
        "Pushing \(dirtyAssetIDs.count) dirty asset(s)",
        level: .notice,
        surface: .sync
      )

      for objectID in dirtyAssetIDs {
        try await pushAsset(objectID: objectID, entityName: assetType.entityName)
      }
    }
  }

  /// Pushes a single asset to Contentful
  /// New assets require file upload; existing assets just update metadata
  private func pushAsset(objectID: NSManagedObjectID, entityName: String) async throws {
    let assetData = try await Asset.fetchPushData(
      objectID: objectID, in: container.viewContext)

    // Fetch current server state
    let serverSys: ContentfulSys?
    do {
      serverSys = try await managementService.fetchMetadata(.asset, id: assetData.id)
    } catch ContentfulManagementError.resourceNotFound {
      serverSys = nil  // New asset, will upload
    }

    // Conflict resolution
    if let serverSys = serverSys,
      config.conflictResolution == .latestWins,
      let serverUpdatedAt = serverSys.updatedAt,
      let localUpdatedAt = assetData.updatedAt,
      serverUpdatedAt > localUpdatedAt
    {
      // Record and log the conflict
      let conflict = ConflictInfo(
        entityType: entityName,
        entityId: assetData.id,
        entityTitle: assetData.title,
        serverDate: serverUpdatedAt,
        localDate: localUpdatedAt
      )
      await MainActor.run {
        skippedConflicts.append(conflict)
      }

      LoggerService.log(
        "Conflict: skipping asset '\(assetData.title ?? assetData.id)' - server newer",
        level: .notice,
        surface: .sync
      )

      await markClean(objectID: objectID, version: serverSys.version)
      return
    }

    if serverSys == nil {
      // NEW ASSET: Download file and upload to Contentful
      guard let urlString = assetData.urlString, let url = URL(string: urlString) else {
        throw ContentfulManagementError.assetUploadFailed(reason: "Asset has no URL")
      }

      let (imageData, _) = try await URLSession.shared.data(from: url)
      let fileName = assetData.fileName ?? "\(assetData.id).jpg"
      let contentType = assetData.fileType ?? "image/jpeg"

      let (uploadedSys, uploadedURL) = try await managementService.uploadAsset(
        id: assetData.id,
        title: assetData.title,
        description: assetData.assetDescription,
        fileData: imageData,
        fileName: fileName,
        contentType: contentType
      )

      // Update local URL and mark clean
      await Asset.updateURLAndMarkClean(
        objectID: objectID, url: uploadedURL, version: uploadedSys.version, in: container)
      LoggerService.log(
        "Uploaded asset '\(assetData.title ?? assetData.id)'",
        level: .debug,
        surface: .sync
      )
    } else {
      // EXISTING ASSET: Just update metadata
      let fields = AssetFieldsPayload.metadata(
        title: assetData.title,
        description: assetData.assetDescription
      )
      let updatedSys = try await managementService.update(
        .asset,
        id: assetData.id,
        version: serverSys!.version,
        fields: fields
      )

      // Publish if configured
      var finalVersion = updatedSys.version
      if config.autoPublish {
        let publishedSys = try await managementService.publish(
          .asset, id: assetData.id, version: updatedSys.version)
        finalVersion = publishedSys.version
      }

      await markClean(objectID: objectID, version: finalVersion)
      LoggerService.log(
        "Updated asset '\(assetData.title ?? assetData.id)'",
        level: .debug,
        surface: .sync
      )
    }
  }

  // MARK: - Generic Entry Push

  /// Generic method to push all dirty objects of a given type
  private func pushDirtyObjects(ofType type: any ContentfulPushable.Type) async throws {
    let dirtyObjectIDs = try await fetchDirtyObjectIDs(entityName: type.entityName)

    guard !dirtyObjectIDs.isEmpty else {
      return
    }

    LoggerService.log(
      "Pushing \(dirtyObjectIDs.count) dirty \(type.entityName)(s)",
      level: .notice,
      surface: .sync
    )

    for objectID in dirtyObjectIDs {
      try await pushObject(ofType: type, objectID: objectID)
    }
  }

  /// Fetches IDs of all dirty objects with a given entity name
  private func fetchDirtyObjectIDs(entityName: String) async throws -> [NSManagedObjectID] {
    let viewContext = container.viewContext
    return try await viewContext.perform {
      let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
      request.predicate = NSPredicate(format: "isDirty == YES")
      let objects = try viewContext.fetch(request)
      return objects.map { $0.objectID }
    }
  }

  /// Pushes a single object to Contentful
  private func pushObject(ofType type: any ContentfulPushable.Type, objectID: NSManagedObjectID)
    async throws
  {
    // Fetch object data from CoreData
    let viewContext = container.viewContext
    let (id, updatedAt, displayTitle, fieldsPayload) = try await viewContext.perform {
      guard let object = try? viewContext.existingObject(with: objectID)
      else {
        throw ContentfulManagementError.resourceNotFound(
          type: type.resourceType, id: objectID.uriRepresentation().absoluteString)
      }

      guard let syncable = object as? (any ContentfulPushable) else {
        throw ContentfulManagementError.resourceNotFound(
          type: type.resourceType, id: objectID.uriRepresentation().absoluteString)
      }

      // Use the protocol extension to encode -- this resolves the concrete type
      let fieldsData = try syncable.encodeFieldsEnvelope()
      return (
        id: syncable.id,
        updatedAt: syncable.updatedAt,
        displayTitle: syncable.displayTitle,
        fields: fieldsData
      )
    }

    // Fetch current server state
    let serverSys: ContentfulSys?
    do {
      serverSys = try await managementService.fetchMetadata(type.resourceType, id: id)
    } catch ContentfulManagementError.resourceNotFound {
      serverSys = nil  // New resource, will create
    }

    // Conflict resolution
    if let serverSys = serverSys,
      config.conflictResolution == .latestWins,
      let serverUpdatedAt = serverSys.updatedAt,
      let localUpdatedAt = updatedAt,
      serverUpdatedAt > localUpdatedAt
    {
      // Record and log the conflict
      let conflict = ConflictInfo(
        entityType: type.entityName,
        entityId: id,
        entityTitle: displayTitle,
        serverDate: serverUpdatedAt,
        localDate: localUpdatedAt
      )
      await MainActor.run {
        skippedConflicts.append(conflict)
      }

      LoggerService.log(
        "Conflict: skipping \(type.entityName) '\(displayTitle ?? id)' - server newer (server: \(serverUpdatedAt), local: \(localUpdatedAt))",
        level: .notice,
        surface: .sync
      )

      // Mark as clean since server has newer data
      await markClean(objectID: objectID, version: serverSys.version)
      return
    }

    // Create or update
    let sys: ContentfulSys
    if let serverSys = serverSys {
      // Update existing -- send pre-encoded fields data
      sys = try await managementService.updateRaw(
        type.resourceType,
        id: id,
        version: serverSys.version,
        fieldsData: fieldsPayload
      )
      LoggerService.log(
        "Updated \(type.entityName) '\(displayTitle ?? id)' to version \(sys.version)",
        level: .debug,
        surface: .sync
      )
    } else {
      // Create new -- send pre-encoded fields data
      sys = try await managementService.createRaw(
        type.resourceType,
        id: id,
        fieldsData: fieldsPayload,
        contentTypeId: type.cmaContentTypeId
      )
      LoggerService.log(
        "Created \(type.entityName) '\(displayTitle ?? id)' at version \(sys.version)",
        level: .debug,
        surface: .sync
      )
    }

    // Publish
    var finalVersion = sys.version
    if config.autoPublish {
      let publishedSys = try await managementService.publish(
        type.resourceType, id: id, version: sys.version)
      finalVersion = publishedSys.version
      LoggerService.log(
        "Published \(type.entityName) '\(displayTitle ?? id)'",
        level: .debug,
        surface: .sync
      )
    }

    // Mark clean with the actual version from the response
    await markClean(objectID: objectID, version: finalVersion)
  }

  /// Marks an object as clean (not dirty) with the given version
  private func markClean(objectID: NSManagedObjectID, version: Int) async {
    // Use a background context so willSave() doesn't mark the object dirty again
    // (willSave only marks dirty for mainQueueConcurrencyType contexts)
    let bgContext = container.newBackgroundContext()
    await bgContext.perform {
      guard let object = try? bgContext.existingObject(with: objectID)
      else { return }
      // Use KVC to set properties generically
      object.setValue(false, forKey: "isDirty")
      object.setValue(version, forKey: "contentfulVersion")
      try? bgContext.save()
    }
  }

  // MARK: - Change Observer

  private func setupChangeObserver() {
    // Observe CoreData saves to track dirty count
    NotificationCenter.default.publisher(
      for: .NSManagedObjectContextDidSave, object: container.viewContext
    )
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
    // Use [weak self] to allow deallocation if mode switches before debounce fires
    syncDebounceTask?.cancel()
    let debounceInterval = config.syncDebounceInterval
    syncDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
      guard !Task.isCancelled else { return }

      do {
        try await self?.sync()
      } catch {
        LoggerService.log("Auto-sync failed", error: error, surface: .sync)
        await MainActor.run { self?.lastError = error }
      }
    }
  }

  private func countDirtyObjects() -> Int {
    var count = 0
    container.viewContext.performAndWait {
      for type in pushableTypes {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: type.entityName)
        request.predicate = NSPredicate(format: "isDirty == YES")
        count += (try? container.viewContext.count(for: request)) ?? 0
      }
    }
    return count
  }
}
