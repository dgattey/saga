//
//  Persistence.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import Contentful
import ContentfulPersistence

/// Handles syncing with Contentful – register new entry types in `PersistenceModel.swift` and ensure your `Config.xcconfig` is set up properly via directions in readme
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    private var syncManager: SynchronizationManager?
    private var client: Client

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Saga")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
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
            persistenceStore: CoreDataStore(context: container.viewContext),
            persistenceModel: PersistenceModel.shared
        )
    }

    func syncWithContentful(completion: @escaping (Result<Void, Error>) -> Void) {
        syncManager?.sync { result in
            switch result {
            case .success:
                print("Contentful sync successful")
                completion(.success(()))
            case .failure(let error):
                print("Contentful sync failed: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Resets all local data and resyncs from server, if needed
    func resetAndSyncWithContentful(completion: @escaping (Result<Void, Error>) -> Void) {
        let context = container.viewContext
        context.perform {
            do {
                guard let entities = context.persistentStoreCoordinator?.managedObjectModel.entities else {
                    completion(.failure(NSError(domain: "No entities", code: 1)))
                    return
                }
                print(entities)
                for entity in entities {
                    guard let name = entity.name else { continue }
                    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: name)
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    try context.execute(deleteRequest)
                }
                try context.save()
                syncWithContentful(completion: completion)
            } catch {
                completion(.failure(error))
            }
        }
    }
}
