//
//  MenuBarCommands.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct MenuBarCommands: Commands {
  @EnvironmentObject var syncViewModel: SyncViewModel
  @EnvironmentObject var cachesViewModel: CachesViewModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
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
        Button("Settings...") {
          showSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: [.command])
      }
    #endif
  }

  #if os(macOS)
    private func showSettingsWindow() {
      // Find existing settings window and bring it to front
      if let settingsWindow = NSApp.windows.first(where: { $0.title == "Settings" }) {
        if settingsWindow.isMiniaturized {
          settingsWindow.deminiaturize(nil)
        }
        settingsWindow.makeKeyAndOrderFront(nil)
      } else {
        // Open new window if none exists
        openWindow(id: "settings")
      }
    }
  #endif
}
