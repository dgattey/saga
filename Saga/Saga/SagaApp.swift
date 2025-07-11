//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

@main
struct SagaApp: App {
    static let persistenceController = PersistenceController.shared
    
    init() {
        // Register our transformers
        RichTextDocumentTransformer.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, Self.persistenceController.container.viewContext)
        }
        Settings {
            SettingsView()
        }
    }
}
