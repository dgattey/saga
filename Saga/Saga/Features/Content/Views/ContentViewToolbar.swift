//
//  ContentViewToolbar.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// The toolbar for the content view
struct ContentViewToolbar: ToolbarContent {
  @Environment(SyncViewModel.self) var viewModel
  @Environment(AnimationSettings.self) var animationSettings
  let navigationHistory: NavigationHistory
  @Binding var entry: NavigationEntry?
  @Binding var isShowingSettings: Bool

  init(
    navigationHistory: NavigationHistory,
    entry: Binding<NavigationEntry?>,
    isShowingSettings: Binding<Bool> = .constant(false)
  ) {
    self.navigationHistory = navigationHistory
    self._entry = entry
    self._isShowingSettings = isShowingSettings
  }

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
      .accessibilityIdentifier(AccessibilityID.Toolbar.backButton)

      Button {
        withAnimation(animationSettings.selectionSpring) {
          navigationHistory.goForward(entry: $entry)
        }
      } label: {
        Image(systemName: "chevron.right")
      }
      .disabled(!navigationHistory.canGoForward)
      .accessibilityLabel("Forward")
      .accessibilityIdentifier(AccessibilityID.Toolbar.forwardButton)
    }
    // Spacer to push sync button to the right when title is hidden
    ToolbarItem(placement: .principal) {
      Spacer()
    }
    ToolbarItemGroup(placement: .primaryAction) {
      Button(action: {
        Task {
          await viewModel.sync()
        }
      }) {
        Label(viewModel.isSyncing ? "Syncing..." : "Sync", systemImage: "arrow.down.circle")
          .labelStyle(.titleAndIcon)
      }
      .disabled(viewModel.isSyncing || viewModel.isResetting)
      .accessibilityIdentifier(AccessibilityID.Toolbar.syncButton)

      #if !os(macOS)
        Button {
          isShowingSettings = true
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(AccessibilityID.Toolbar.settingsButton)
      #endif
    }
  }
}
