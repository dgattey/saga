//
//  PersistenceService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

@preconcurrency import Contentful
@preconcurrency import CoreData
import DylCore
import Foundation

enum PersistenceSyncError: LocalizedError, Equatable {
  case missingCredentials

  var errorDescription: String? {
    "Contentful credentials are missing or set to placeholder values."
  }

  var recoverySuggestion: String? {
    "Run 'scripts/bootstrap.sh' to set Contentful credentials."
  }
}

/// Handles syncing with Contentful and persisting entries in Core Data.
struct PersistenceService: Sendable {
  typealias SyncFetcher = @Sendable (String) async throws -> SyncSpace

  private static let syncTokenMetadataKey = "ContentfulSyncToken"

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
  private let client: Client
  private let hasValidCredentials: Bool
  var syncFetcher: SyncFetcher?

  init(
    inMemory: Bool = Self.isRunningUnitTests,
    container: NSPersistentContainer? = nil,
    spaceId: String = BundleKey.spaceId.bundleValue,
    accessToken: String = BundleKey.accessToken.bundleValue,
    syncFetcher: SyncFetcher? = nil
  ) {
    let persistentContainer =
      container
      ?? NSPersistentContainer(name: "Saga", managedObjectModel: Self.managedObjectModel)
    if container == nil {
      if inMemory {
        persistentContainer.persistentStoreDescriptions = [
          NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        ]
      } else if let storePath = LaunchOverrides.current.storePath {
        persistentContainer.persistentStoreDescriptions = [
          NSPersistentStoreDescription(url: URL(fileURLWithPath: storePath))
        ]
      }
      persistentContainer.loadPersistentStores { description, error in
        guard error != nil, let url = description.url else { return }
        try? persistentContainer.persistentStoreCoordinator.destroyPersistentStore(
          at: url, type: .sqlite
        )
      }
      if persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty {
        persistentContainer.loadPersistentStores { _, error in
          if let error = error as NSError? {
            fatalError("Unresolved error \(error), \(error.userInfo)")
          }
        }
      }
      persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
      persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    self.container = persistentContainer
    self.hasValidCredentials = ![spaceId, accessToken].contains {
      let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty || trimmed.lowercased() == "placeholder"
    }
    self.syncFetcher = syncFetcher
    self.client = Client(spaceId: spaceId, environmentId: "master", accessToken: accessToken)
  }

  /// Synchronizes with Contentful CDA. When `reset` is true, fetches a full initial sync first
  /// and replaces local records only after the remote payload arrives.
  func syncWithApi(reset: Bool = false) async throws {
    let token =
      reset
      ? ""
      : await container.performBackgroundTask {
        guard let coordinator = $0.persistentStoreCoordinator,
          let store = coordinator.persistentStores.first
        else { return "" }
        return coordinator.metadata(for: store)[Self.syncTokenMetadataKey] as? String ?? ""
      }
    let syncSpace = try await fetchRemoteSyncSpace(syncToken: token)

    try await container.performBackgroundTask { context in
      context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

      if reset {
        for entityName in ["Book", "Asset"] {
          let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
          request.includesPropertyValues = false
          try context.fetch(request).forEach(context.delete)
        }
      }

      var assetsByID = Dictionary(
        try context.fetch(NSFetchRequest<Asset>(entityName: "Asset")).map { ($0.id, $0) },
        uniquingKeysWith: { _, latest in latest }
      )
      for remoteAsset in syncSpace.assets {
        let asset = assetsByID[remoteAsset.id] ?? Asset(context: context)
        asset.apply(remoteAsset)
        assetsByID[remoteAsset.id] = asset
      }

      var booksByID = Dictionary(
        try context.fetch(NSFetchRequest<Book>(entityName: "Book")).map { ($0.id, $0) },
        uniquingKeysWith: { _, latest in latest }
      )
      for remoteEntry in syncSpace.entries where remoteEntry.sys.contentTypeId == Book.contentTypeId
      {
        let book = booksByID[remoteEntry.id] ?? Book(context: context)
        book.apply(remoteEntry, assetsByID: assetsByID)
        booksByID[remoteEntry.id] = book
      }

      if !reset {
        for id in syncSpace.deletedAssetIds {
          assetsByID.removeValue(forKey: id).map(context.delete)
        }
        for id in syncSpace.deletedEntryIds {
          booksByID.removeValue(forKey: id).map(context.delete)
        }
      }

      if let coordinator = context.persistentStoreCoordinator,
        let store = coordinator.persistentStores.first
      {
        var metadata = coordinator.metadata(for: store)
        metadata[Self.syncTokenMetadataKey] = syncSpace.syncToken
        coordinator.setMetadata(metadata, for: store)
      }
      if context.hasChanges {
        try context.save()
      }
    }

    if reset {
      await MainActor.run {
        container.viewContext.refreshAllObjects()
      }
    }
    LoggerService.log("Contentful sync successful", level: .debug, surface: .persistence)
  }

  private func fetchRemoteSyncSpace(syncToken: String) async throws -> SyncSpace {
    if let syncFetcher {
      return try await syncFetcher(syncToken)
    }
    guard hasValidCredentials else {
      let error = PersistenceSyncError.missingCredentials
      LoggerService.log("Contentful sync aborted", error: error, surface: .persistence)
      throw error
    }
    let initialSpace = syncToken.isEmpty ? SyncSpace() : SyncSpace(syncToken: syncToken)
    let client = self.client
    return try await withCheckedThrowingContinuation { continuation in
      client.sync(for: initialSpace) { result in
        switch result {
        case .success(let space):
          continuation.resume(returning: space)
        case .failure(let error):
          LoggerService.log("Contentful sync failed", error: error, surface: .persistence)
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
