//
//  PersistenceService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

@preconcurrency import Contentful
@preconcurrency import ContentfulPersistence
@preconcurrency import CoreData
import DylCore

/// Handles syncing with Contentful – register new entry types in `PersistenceModel.swift` and ensure your `Config.xcconfig` is set up properly via directions in readme
struct PersistenceService: Sendable {
  static var isRunningUnitTests: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil
      || env["XCTestSessionIdentifier"] != nil
      || env["XCTestBundlePath"] != nil
      || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
  }

  static let managedObjectModel: NSManagedObjectModel = {
    guard let modelURL = Bundle.main.url(forResource: "Saga", withExtension: "momd") else {
      fatalError("Saga.momd missing from main bundle")
    }
    return loadManagedObjectModel(at: modelURL)
  }()

  /// Loads a compiled `Saga.momd`; unit tests pass one compiled outside the app bundle.
  static func loadManagedObjectModel(at modelURL: URL) -> NSManagedObjectModel {
    RichTextDocumentTransformer.register()
    guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
      fatalError("Failed to load Saga NSManagedObjectModel from \(modelURL.path)")
    }
    return model
  }

  let container: NSPersistentContainer
  private var syncManager: SynchronizationManager
  private var client: Client

  init(inMemory: Bool = Self.isRunningUnitTests) {
    container = NSPersistentContainer(name: "Saga", managedObjectModel: Self.managedObjectModel)
    if inMemory {
      let description = NSPersistentStoreDescription()
      description.url = URL(fileURLWithPath: "/dev/null")
      container.persistentStoreDescriptions = [description]
    } else if let storePath = LaunchOverrides.current.storePath {
      let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: storePath))
      container.persistentStoreDescriptions = [description]
    }
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
  }

  /// Actually executes a sync with the Contentful API
  func syncWithApi() async throws {
    try await withCheckedThrowingContinuation { continuation in
      syncManager.sync { result in
        switch result {
        case .success:
          LoggerService.log("Contentful sync successful", level: .debug, surface: .persistence)
          continuation.resume()
        case .failure(let error):
          LoggerService.log("Contentful sync failed", error: error, surface: .persistence)
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Resets all local data and resyncs from server, if needed
  func resetAndSyncWithApi() async throws {
    let entityNames = container.managedObjectModel.entities.compactMap { $0.name }
    LoggerService.log(
      "Resetting \(entityNames.count) entities: \(entityNames.joined(separator: ", "))",
      level: .debug,
      surface: .persistence
    )

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
          fromRemoteContextSave: changes, into: [container.viewContext])
      }
    }
    LoggerService.log("Erased all entities", level: .debug, surface: .persistence)
    try await syncWithApi()
  }
}
