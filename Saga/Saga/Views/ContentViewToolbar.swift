//
//  ContentViewToolbar.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// The toolbar for the content view
struct ContentViewToolbar: ToolbarContent {
    let add: () -> Void
    let sync: () -> Void

    var body: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
        }
#endif
        ToolbarItem {
            Button(action: add) {
                Label("Add Item", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button(action: sync) {
                Label("Sync", systemImage: "arrow.clockwise")
            }
        }
    }
}
