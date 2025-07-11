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
        // Register our transformers
        RichTextDocumentTransformer.register()
        
        // Sync with API at launch
        Task {
            do {
                try await PersistenceController.shared.syncWithApi()
            } catch {
                print("Error doing initial sync: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        Settings {
            SettingsView()
        }
    }
}
