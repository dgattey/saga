//
//  MenuBarCommands.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import SwiftUI

struct MenuBarCommands: Commands {
  @EnvironmentObject var viewModel: SyncViewModel

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()

      Button("Refresh") {
        Task {
          await viewModel.sync()
        }
      }
      .disabled(viewModel.isSyncing)
      .keyboardShortcut("r", modifiers: [.command])

      Button("Clear cache and refresh") {
        Task {
          await viewModel.resetAndSync()
        }
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      .disabled(viewModel.isSyncing)
    }
  }
}
