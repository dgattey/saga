//
//  MenuBarCommands.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import SwiftUI

struct MenuBarCommands: Commands {
  @Environment(SyncViewModel.self) var syncViewModel
  @Environment(CachesViewModel.self) var cachesViewModel
  @Environment(BooksViewModel.self) var booksViewModel
  #if os(macOS)
    @Environment(UpdaterViewModel.self) var updaterViewModel
  #endif
  @Environment(\.openWindow) private var openWindow
  @FocusedBinding(\.isCreatingBook) private var isCreatingBook

  var body: some Commands {
    #if os(macOS)
      CommandGroup(after: .appInfo) {
        CheckForUpdatesMenuItem(updaterViewModel: updaterViewModel)
      }
    #endif

    CommandGroup(replacing: .newItem) {
      Button("New Book…") {
        isCreatingBook = true
      }
      .keyboardShortcut("n", modifiers: [.command])
      .disabled(isCreatingBook == nil)
    }

    // Lives in the File menu so ⌘F wins over the Edit menu's Find item.
    CommandGroup(after: .newItem) {
      Button("Search Books…") {
        booksViewModel.isSpotlightPresented.toggle()
      }
      .keyboardShortcut("k", modifiers: [.command])

      Button("Search Sidebar") {
        booksViewModel.isSpotlightPresented = false
        booksViewModel.sidebarSearchFocusRequests.send()
      }
      .keyboardShortcut("f", modifiers: [.command])

      Divider()

      Button("Refresh data") {
        Task {
          await syncViewModel.sync()
        }
      }
      .disabled(syncViewModel.isSyncing)
      .keyboardShortcut("r", modifiers: [.command])

      Button("Clear caches") {
        Task {
          await cachesViewModel.clearAll()
        }
      }
      .keyboardShortcut("k", modifiers: [.command, .shift])
      .disabled(syncViewModel.isSyncing)

      Button("Clear all local data") {
        Task {
          await cachesViewModel.clearAll()
          await syncViewModel.resetAndSync()
        }
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      .disabled(syncViewModel.isSyncing)
    }

    #if os(macOS)
      CommandGroup(replacing: .appSettings) {
        // `Window` scenes are single-instance, so this focuses an already open Settings window.
        Button("Settings...") {
          openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: [.command])
      }
    #endif
  }
}

extension FocusedValues {
  @Entry var isCreatingBook: Binding<Bool>?
}
