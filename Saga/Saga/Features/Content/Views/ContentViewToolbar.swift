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
  @EnvironmentObject var animationSettings: AnimationSettings
  @ObservedObject var navigationHistory: NavigationHistory
  @Binding var entry: NavigationEntry?

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        withAnimation(animationSettings.selectionSpring) {
          navigationHistory.goBack(entry: $entry)
        }
      } label: {
        Image(systemName: "chevron.left")
      }
      .disabled(!navigationHistory.canGoBack)
      .accessibilityLabel("Back")

      Button {
        withAnimation(animationSettings.selectionSpring) {
          navigationHistory.goForward(entry: $entry)
        }
      } label: {
        Image(systemName: "chevron.right")
      }
      .disabled(!navigationHistory.canGoForward)
      .accessibilityLabel("Forward")
    }
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
