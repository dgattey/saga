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
    @StateObject private var contentViewModel = BooksViewModel()
    
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
            SidebarCommands()
        }
        .environmentObject(viewModel)
        .environmentObject(contentViewModel)
        .defaultSize(width: 1000, height: 600)
        
        Settings {
            SettingsView()
        }
        .environmentObject(viewModel)
    }
}
