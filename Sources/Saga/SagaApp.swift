//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import DylUI
import SwiftUI

@main
struct SagaApp: App {
  @State private var syncViewModel = SyncViewModel()
  @State private var cachesViewModel = CachesViewModel()
  @State private var booksViewModel = BooksViewModel()
  @State private var animationSettings = AnimationSettings.shared

  init() {
    RichTextDocumentTransformer.register()
  }

  var body: some Scene {
    AppWindow(
      "Saga",
      palette: SagaPalette(),
      defaultSize: CGSize(width: 1000, height: 600)
    ) {
      ContentView()
        .environment(\.managedObjectContext, syncViewModel.viewContext)
        .windowBackground()
    } commands: {
      MenuBarCommands()
      SidebarCommands()
    }
    .environment(syncViewModel)
    .environment(cachesViewModel)
    .environment(booksViewModel)
    .environment(animationSettings)

    #if os(macOS)
      Window("Settings", id: "settings") {
        SettingsView()
          .palette(SagaPalette())
          .windowBackground()
      }
      .windowResizability(.contentSize)
      .defaultSize(width: 700, height: 540)
      .restorationBehavior(.disabled)
      .handlesExternalEvents(matching: ["settings"])
      .environment(syncViewModel)
      .environment(cachesViewModel)
      .environment(animationSettings)
    #endif
  }
}
