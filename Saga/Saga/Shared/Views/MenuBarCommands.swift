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
        CommandGroup(after: .pasteboard) {
            Divider()
            
            Button("Find") {
                if let toolbar = NSApp.keyWindow?.toolbar,
                   let search = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "com.apple.SwiftUI.search" }) as? NSSearchToolbarItem {
                    search.beginSearchInteraction()
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
