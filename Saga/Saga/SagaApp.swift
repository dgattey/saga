//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

@main
struct SagaApp: App {
    let persistenceController = PersistenceController.shared
    
    init() {
        // Sync with Contentful at launch
        persistenceController.syncWithContentful { result in
            switch result {
            case .success:
                print("Synced with Contentful on startup!")
            case .failure(let error):
                print("Error syncing with Contentful: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
