//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

@main
struct SagaApp: App {
    @StateObject private var viewModel = SyncViewModel()
    
    init() {
        // Register our transformers
        RichTextDocumentTransformer.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, viewModel.viewContext)
        }
        .commands {
            MenuBarCommands()
        }
        .environmentObject(viewModel)
        
        Settings {
            SettingsView()
        }
        .environmentObject(viewModel)
    }
}
