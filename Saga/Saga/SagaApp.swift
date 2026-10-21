//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

@main
struct SagaApp: App {
  @State private var syncViewModel = SyncViewModel()
  @State private var cachesViewModel = CachesViewModel()
  @State private var booksViewModel = BooksViewModel()
  @State private var animationSettings = AnimationSettings.shared
  #if os(macOS)
    @State private var updaterViewModel = UpdaterViewModel()
  #endif

  init() {
    // Register our transformers
    RichTextDocumentTransformer.register()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, syncViewModel.viewContext)
        .windowBackground()
        .preferredColorScheme(LaunchOptions.colorScheme)
        #if os(macOS)
          .onAppear {
            updaterViewModel.mainWindowDidAppear()
          }
        #endif
    }
    .commands {
      MenuBarCommands()
      SidebarCommands()
    }
    .environment(syncViewModel)
    .environment(cachesViewModel)
    .environment(booksViewModel)
    .environment(animationSettings)
    #if os(macOS)
      .environment(updaterViewModel)
    #endif
    .defaultSize(width: 1000, height: 600)

    #if os(macOS)
      Window("Settings", id: "settings") {
        SettingsView()
          .windowBackground()
      }
      .windowResizability(.contentSize)
      .defaultSize(width: 680, height: 520)
      .restorationBehavior(.disabled)
      .handlesExternalEvents(matching: ["settings"])
      .environment(syncViewModel)
      .environment(cachesViewModel)
      .environment(animationSettings)
      .environment(updaterViewModel)
    #endif
  }
}
