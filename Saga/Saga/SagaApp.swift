//
//  SagaApp.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

@main
struct SagaApp: App {
  @StateObject private var syncViewModel = SyncViewModel()
  @StateObject private var cachesViewModel = CachesViewModel()
  @StateObject private var booksViewModel = BooksViewModel()
  @StateObject private var animationSettings = AnimationSettings.shared
  #if os(macOS)
    @StateObject private var updaterViewModel = UpdaterViewModel()
  #endif

  init() {
    // Register our transformers
    RichTextDocumentTransformer.register()

    #if os(macOS)
      if PersistenceService.isRunningUnitTests {
        // Prevent unit test host from showing a Dock icon, creating a visible window, or stealing focus
        NSApp?.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
          forName: NSApplication.didFinishLaunchingNotification,
          object: nil,
          queue: .main
        ) { _ in
          NSApp.setActivationPolicy(.accessory)
          for window in NSApp.windows {
            window.orderOut(nil)
          }
        }
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      if PersistenceService.isRunningUnitTests {
        EmptyView()
      } else {
        ContentView()
          .environment(\.managedObjectContext, syncViewModel.viewContext)
          .windowBackground()
          .hotReloadable()
          #if os(macOS)
            .onAppear {
              updaterViewModel.mainWindowDidAppear()
            }
          #endif
      }
    }
    .commands {
      MenuBarCommands()
      SidebarCommands()
    }
    .environmentObject(syncViewModel)
    .environmentObject(cachesViewModel)
    .environmentObject(booksViewModel)
    .environmentObject(animationSettings)
    #if os(macOS)
      .environmentObject(updaterViewModel)
    #endif
    .defaultSize(width: 1000, height: 600)

    #if os(macOS)
      Window("Settings", id: "settings") {
        SettingsView()
          .hotReloadable()
      }
      .windowResizability(.contentSize)
      .defaultSize(width: 640, height: 460)
      .restorationBehavior(.disabled)
      .handlesExternalEvents(matching: ["settings"])
      .environmentObject(syncViewModel)
      .environmentObject(cachesViewModel)
      .environmentObject(animationSettings)
      .environmentObject(updaterViewModel)
    #endif
  }
}
