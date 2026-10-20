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
  #if os(macOS)
    @Environment(UpdaterViewModel.self) var updaterViewModel
  #endif
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    #if os(macOS)
      CommandGroup(after: .appInfo) {
        CheckForUpdatesMenuItem(updaterViewModel: updaterViewModel)
      }
    #endif

    CommandGroup(after: .newItem) {
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
