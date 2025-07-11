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
#if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
        }
#endif
        ToolbarItem {
            Button(action: {
                Task {
                    await viewModel.sync()
                }
            }) {
                Label("Sync", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isSyncing)
        }
    }
}
