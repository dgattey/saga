//
//  Persistence.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import Contentful
import ContentfulPersistence

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    var syncManager: SynchronizationManager?

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
        let spaceId = Bundle.main.object(forInfoDictionaryKey: "ContentfulSpaceId") as? String ?? ""
        let accessToken = Bundle.main.object(forInfoDictionaryKey: "ContentfulAccessToken") as? String ?? ""
        let client = Client(
            spaceId: spaceId,
            environmentId: "master",
            accessToken: accessToken
        )
        let persistenceModel = PersistenceModel(
            spaceType: SyncSpace.self,
            assetType: Asset.self,
            entryTypes: [Book.self]
        )
        syncManager = SynchronizationManager(
            client: client,
            localizationScheme: .default,
            persistenceStore: CoreDataStore(context: container.viewContext),
            persistenceModel: persistenceModel
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
}
