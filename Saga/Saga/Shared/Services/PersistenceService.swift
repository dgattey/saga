//
//  PersistenceService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import ContentfulPersistence
import CoreData

/// Handles syncing with Contentful – register new entry types in `PersistenceModel.swift` and ensure your `Config.xcconfig` is set up properly via directions in readme
///
/// ## Two-Way Sync
/// This service now supports bidirectional sync:
/// - **Pull** (Contentful → CoreData): Uses ContentfulPersistence's SynchronizationManager with delta sync tokens
/// - **Push** (CoreData → Contentful): Uses the Content Management API via TwoWaySyncService
///
/// To enable push (two-way sync), add `ContentfulManagementToken` to your Config.xcconfig.
/// Without this token, only pull (one-way sync) is available.
///
/// ### How It Works
/// 1. CoreData changes are automatically detected via `NSManagedObjectContextDidSaveNotification`
/// 2. Changes are debounced and batched for efficiency
/// 3. Conflicts are resolved using "latest-wins" based on `updatedAt` timestamps
/// 4. Assets are uploaded to Contentful and their URLs are updated locally
struct PersistenceService {
  let container: NSPersistentContainer

  /// The two-way sync service (handles both pull and push)
  let twoWaySyncService: TwoWaySyncService

  /// Legacy access to sync manager for compatibility
  private var syncManager: SynchronizationManager
  private var client: Client

  /// Whether two-way sync (push to Contentful) is available
  var isTwoWaySyncEnabled: Bool {
    BundleKey.hasManagementToken
  }

  init() {
    container = NSPersistentContainer(name: "Saga")
    container.loadPersistentStores { (storeDescription, error) in
      if let error = error as NSError? {
        fatalError("Unresolved error \(error), \(error.userInfo)")
      }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true

    // --- Contentful setup ---
    client = Client(
      spaceId: BundleKey.spaceId.bundleValue,
      environmentId: "master",
      accessToken: BundleKey.accessToken.bundleValue
    )
    syncManager = SynchronizationManager(
      client: client,
      localizationScheme: .default,
      persistenceStore: CoreDataStore(context: container.newBackgroundContext()),
      persistenceModel: PersistenceModel.shared
    )

    // --- Initialize two-way sync service ---
    twoWaySyncService = TwoWaySyncService(
      container: container,
      syncManager: syncManager,
      config: TwoWaySyncConfig(
        autoPushEnabled: true,
        pushDebounceInterval: 2.0,
        autoPublish: true,
        conflictResolution: .latestWins
      )
    )

    // --- Creation kicks off an initial sync ---
    Task { [self] in
      do {
        try await syncWithApi()
      } catch {
        LoggerService.log("Initial sync failed", error: error, surface: .persistence)
      }
    }
  }

  /// Pulls changes from Contentful to CoreData (one-way sync)
  /// This is the original sync behavior using ContentfulPersistence
  func syncWithApi() async throws {
    try await twoWaySyncService.pull()
  }

  /// Pushes local changes to Contentful (requires management token)
  /// Call this to manually trigger a push, or rely on automatic push
  func pushToContentful() async throws {
    try await twoWaySyncService.push()
  }

  /// Performs a full bidirectional sync: pull then push
  func fullSync() async throws {
    try await twoWaySyncService.sync()
  }

  /// Resets all local data and resyncs from server, if needed
  func resetAndSyncWithApi() async throws {
    try await twoWaySyncService.resetAndSync()
  }
}
