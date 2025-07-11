//
//  ContentViewToolbar.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// The toolbar for the content view
struct ContentViewToolbar: ToolbarContent {

    var body: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
        }
#endif
        ToolbarItem {
            Button(action: {
                Task {
                    do {
                        try await PersistenceController.shared.syncWithApi()
                    } catch {
                        print("Error syncing: \(error)")
                    }
                }
            }) {
                Label("Sync", systemImage: "arrow.clockwise")
            }
        }
    }
}
