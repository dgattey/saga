//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

@main
struct SagaApp: App {
  @StateObject private var syncViewModel = SyncViewModel()
  @StateObject private var cachesViewModel = CachesViewModel()
  @StateObject private var booksViewModel = BooksViewModel()

  init() {
    // Register our transformers
    RichTextDocumentTransformer.register()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, syncViewModel.viewContext)
        .windowBackground()
    }
    .commands {
      MenuBarCommands()
      SidebarCommands()
    }
    .environmentObject(syncViewModel)
    .environmentObject(cachesViewModel)
    .environmentObject(booksViewModel)
    .defaultSize(width: 1000, height: 600)

    #if os(macOS)
      Settings {
        SettingsView()
          .windowBackground()
      }
      .environmentObject(syncViewModel)
      .environmentObject(cachesViewModel)
    #endif
  }
}
