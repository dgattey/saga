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
#if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.leading")
            }
        }
#endif
    }
    
    private func toggleSidebar() {
#if os(macOS)
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
#endif
    }
}
