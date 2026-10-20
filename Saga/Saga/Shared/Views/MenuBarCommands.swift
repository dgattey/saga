//
//  MenuBarCommands.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import SwiftUI

struct MenuBarCommands: Commands {
  @EnvironmentObject var syncViewModel: SyncViewModel
  @EnvironmentObject var cachesViewModel: CachesViewModel
  #if os(macOS)
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
  #endif
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.newBookAction) private var newBookAction

  var body: some Commands {
    #if os(macOS)
      CommandGroup(after: .appInfo) {
        CheckForUpdatesMenuItem(updaterViewModel: updaterViewModel)
      }
    #endif

    CommandGroup(replacing: .newItem) {
      Button("New Book…") {
        newBookAction?.callAsFunction()
      }
      .keyboardShortcut("n", modifiers: [.command])
      .disabled(newBookAction == nil)
    }

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
