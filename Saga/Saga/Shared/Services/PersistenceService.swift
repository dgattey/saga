//
//  PersistenceService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import ContentfulPersistence
import CoreData

/// Handles two-way sync with Contentful.
///
/// **REQUIRED**: Configure `CONTENTFUL_MANAGEMENT_TOKEN` in Config.xcconfig.
/// The app will crash at startup if this is missing.
///
/// ## Sync Workflow
/// 1. User edits CoreData object → `isDirty = true` (automatic via `willSave()`)
/// 2. On sync: Pull from Contentful first (delta sync)
/// 3. Fetch `sys.version` from CMA for each dirty object
/// 4. Resolve conflicts (latest-wins via `updatedAt`)
/// 5. Push changes via CMA
/// 6. Explicitly publish entries
/// 7. Mark `isDirty = false`, update `contentfulVersion`
struct PersistenceService {
  let container: NSPersistentContainer
  let twoWaySyncService: TwoWaySyncService

  init() {
    container = NSPersistentContainer(name: "Saga")
    container.loadPersistentStores { (storeDescription, error) in
      if let error = error as NSError? {
        fatalError("Unresolved error \(error), \(error.userInfo)")
      }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true

    // --- Contentful CDA setup (for pull) ---
    let client = Client(
      spaceId: BundleKey.spaceId.bundleValue,
      environmentId: "master",
      accessToken: BundleKey.accessToken.bundleValue
    )
    let syncManager = SynchronizationManager(
      client: client,
      localizationScheme: .default,
      persistenceStore: CoreDataStore(context: container.newBackgroundContext()),
      persistenceModel: PersistenceModel.shared
    )

    // --- Two-way sync service (REQUIRED - will crash if token missing) ---
    do {
      twoWaySyncService = try TwoWaySyncService(
        container: container,
        syncManager: syncManager,
        config: TwoWaySyncConfig(
          syncDebounceInterval: 2.0,
          autoPublish: true,
          conflictResolution: .latestWins
        )
      )
    } catch {
      fatalError("""
        Two-way sync requires CONTENTFUL_MANAGEMENT_TOKEN in Config.xcconfig.

        Get your token from: Contentful → Settings → API keys → Content management tokens

        Add to Saga/Config/Config.xcconfig:
        CONTENTFUL_MANAGEMENT_TOKEN = your_token_here
        """)
    }

    // --- Initial sync on launch ---
    Task { [self] in
      do {
        try await sync()
      } catch {
        LoggerService.log("Initial sync failed", error: error, surface: .persistence)
      }
    }
  }

  /// Performs a full bidirectional sync: pull from Contentful, then push dirty local changes
  func sync() async throws {
    try await twoWaySyncService.sync()
  }

  /// Resets all local data and resyncs from Contentful
  func resetAndSync() async throws {
    try await twoWaySyncService.resetAndSync()
  }
}
