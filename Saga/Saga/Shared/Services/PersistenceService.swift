//
//  PersistenceService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

@preconcurrency import Contentful
import ContentfulPersistence
import CoreData

/// Handles two-way sync with Contentful.
///
/// **REQUIRED**: Configure `CONTENTFUL_MANAGEMENT_ACCESS_TOKEN` in Config.xcconfig.
/// The app will crash at startup if this is missing.
///
/// ## Sync Workflow
/// 1. User edits CoreData object → `isDirty = true` (automatic via `willSave()`)
/// 2. On sync: Pull from Contentful first (delta sync or full fetch in preview mode)
/// 3. Fetch `sys.version` from CMA for each dirty object
/// 4. Resolve conflicts (latest-wins via `updatedAt`)
/// 5. Push changes via CMA
/// 6. Explicitly publish entries (if autoPublish is enabled)
/// 7. Mark `isDirty = false`, update `contentfulVersion`
///
/// ## Preview Mode
/// When `usePreviewContent` is true, reads use the Content Preview API (draft + published content)
/// and `autoPublish` is disabled so edits stays as drafts.
struct PersistenceService {
  /// Shared Core Data container - MUST be singleton to avoid corruption
  static let sharedContainer: NSPersistentContainer = {
    let container = NSPersistentContainer(name: "Saga")
    container.loadPersistentStores { (storeDescription, error) in
      if let error = error as NSError? {
        fatalError("Unresolved error \(error), \(error.userInfo)")
      }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true
    return container
  }()

  let container: NSPersistentContainer
  let twoWaySyncService: TwoWaySyncService
  let usePreviewContent: Bool

  init(usePreviewContent: Bool = false) {
    self.usePreviewContent = usePreviewContent
    self.container = Self.sharedContainer

    // --- Contentful client setup ---
    // Preview mode uses Content Preview API (draft + published); delivery mode uses CDA (published only)
    let accessToken =
      usePreviewContent
      ? BundleKey.previewAccessToken.bundleValue : BundleKey.accessToken.bundleValue
    let host = usePreviewContent ? Contentful.Host.preview : Contentful.Host.delivery
    let client = Client(
      spaceId: BundleKey.spaceId.bundleValue,
      environmentId: "master",
      accessToken: accessToken,
      host: host
    )

    // --- Build pull closure ---
    // Delivery mode uses SynchronizationManager's delta sync; preview mode fetches directly
    // because the Content Preview API does not support the /sync endpoint.
    let pull: () async throws -> Void
    if usePreviewContent {
      pull = Self.makePreviewPull(client: client, container: container)
    } else {
      let syncManager = SynchronizationManager(
        client: client,
        localizationScheme: .default,
        persistenceStore: CoreDataStore(context: container.newBackgroundContext()),
        persistenceModel: PersistenceModel.shared
      )
      pull = Self.makeDeliveryPull(syncManager: syncManager)
    }

    // --- Two-way sync service (REQUIRED - will crash if token missing) ---
    // In preview mode, autoPublish is disabled so edits stay as drafts
    do {
      twoWaySyncService = try TwoWaySyncService(
        container: container,
        pull: pull,
        pushableTypes: [Asset.self, Book.self],
        config: TwoWaySyncConfig(
          syncDebounceInterval: 2.0,
          autoPublish: !usePreviewContent,
          conflictResolution: .latestWins
        )
      )
    } catch {
      fatalError(
        """
        Two-way sync requires CONTENTFUL_MANAGEMENT_ACCESS_TOKEN in Config.xcconfig.

        Get your token from: Contentful → Settings → API keys → Content management tokens

        Add to Saga/Config/Config.xcconfig (or run bootstrap to pull from 1Password):
        CONTENTFUL_MANAGEMENT_ACCESS_TOKEN = your_token_here
        """)
    }

    // NOTE: Caller (SyncViewModel) is responsible for triggering initial sync.
    // This avoids race conditions when switching preview modes.
  }

  /// Performs a full bidirectional sync: pull from Contentful, then push dirty local changes
  func sync() async throws {
    try await twoWaySyncService.sync()
  }

  /// Resets all local data and resyncs from Contentful
  func resetAndSync() async throws {
    try await twoWaySyncService.resetAndSync()
  }

  // MARK: - Pull Strategies

  /// Creates a pull closure that uses SynchronizationManager's delta sync (delivery mode)
  private static func makeDeliveryPull(syncManager: SynchronizationManager) -> () async throws
    -> Void
  {
    return {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        syncManager.sync { result in
          switch result {
          case .success:
            continuation.resume()
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  /// Creates a pull closure that fetches content directly from the preview API
  /// (the Content Preview API does not support the /sync endpoint)
  private static func makePreviewPull(
    client: Client, container: NSPersistentContainer
  ) -> () async throws -> Void {
    return {
      // Fetch all assets first (books reference them)
      let assets: HomogeneousArrayResponse<Contentful.Asset> =
        try await withCheckedThrowingContinuation { continuation in
          client.fetchArray(of: Contentful.Asset.self) { result in
            continuation.resume(with: result)
          }
        }

      // Fetch all book entries
      let bookQuery = Query.where(contentTypeId: Book.contentTypeId)
      let entries: HomogeneousArrayResponse<Entry> =
        try await withCheckedThrowingContinuation { continuation in
          client.fetchArray(of: Entry.self, matching: bookQuery) { result in
            continuation.resume(with: result)
          }
        }

      // Upsert into Core Data (each model owns its own upsert logic)
      let bgContext = container.newBackgroundContext()
      try await bgContext.perform {
        for contentfulAsset in assets.items {
          Asset.upsert(from: contentfulAsset, in: bgContext)
        }
        for entry in entries.items {
          Book.upsert(from: entry, in: bgContext)
        }
        try bgContext.save()
      }

      LoggerService.log(
        "Preview pull completed: \(entries.items.count) books, \(assets.items.count) assets",
        level: .debug,
        surface: .sync
      )
    }
  }

}
