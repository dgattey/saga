//
//  ContentViewToolbar.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// The toolbar for the content view
struct ContentViewToolbar: ToolbarContent {
    @EnvironmentObject var viewModel: SyncViewModel

    var body: some ToolbarContent {
        // Spacer to push sync button to the right when title is hidden
        ToolbarItem(placement: .principal) {
            Spacer()
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                Task {
                    await viewModel.sync()
                }
            }) {
                Label(viewModel.isSyncing ? "Syncing..." : "Sync", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(viewModel.isSyncing || viewModel.isResetting)
        }
    }
}
