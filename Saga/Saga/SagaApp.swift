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

  init() {
    // Register our transformers
    RichTextDocumentTransformer.register()

    #if DEBUG
      // Load InjectionIII bundle for hot reload support
      #if os(macOS)
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
      #elseif os(tvOS)
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/tvOSInjection.bundle")?.load()
      #else
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
      #endif
    #endif

    #if os(macOS)
      // Close any restored settings window after app finishes launching
      NotificationCenter.default.addObserver(
        forName: NSApplication.didFinishLaunchingNotification,
        object: nil,
        queue: .main
      ) { _ in
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0
          for window in NSApp.windows where window.title == "Settings" {
            window.close()
          }
        }
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.managedObjectContext, syncViewModel.viewContext)
        .windowBackground()
        .hotReloadable()
    }
    .commands {
      MenuBarCommands()
      SidebarCommands()
    }
    .environmentObject(syncViewModel)
    .environmentObject(cachesViewModel)
    .environmentObject(booksViewModel)
    .environmentObject(animationSettings)
    .defaultSize(width: 1000, height: 600)

    #if os(macOS)
      WindowGroup("Settings", id: "settings") {
        SettingsView()
          .windowBackground()
          .hotReloadable()
      }
      .windowResizability(.contentSize)
      .defaultSize(width: 450, height: 650)
      .handlesExternalEvents(matching: ["settings"])
      .environmentObject(syncViewModel)
      .environmentObject(cachesViewModel)
      .environmentObject(animationSettings)
    #endif
  }
}
