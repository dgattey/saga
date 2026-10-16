//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// Settings shell: a native floating-sidebar split view on macOS and a pushed list on iOS. Each
/// pane is a grouped `Form`, and selection uses the stock system highlight.
struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var cachesViewModel: CachesViewModel

  @State private var selectedPane: SettingsPane?

  init(initialPane: SettingsPane = .general) {
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    Group {
      #if os(macOS)
        splitLayout
      #else
        stackLayout
      #endif
    }
    .accessibilityIdentifier(AccessibilityID.Settings.view)
    .onAppear {
      cachesViewModel.startMonitoring()
    }
    .onDisappear {
      cachesViewModel.stopMonitoring()
    }
  }

  // MARK: - Platform Layouts

  #if os(macOS)
    private var splitLayout: some View {
      NavigationSplitView {
        List(selection: $selectedPane) {
          ForEach(SettingsPane.allCases) { pane in
            paneLabel(for: pane)
              .tag(pane)
          }
        }
        .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
        .navigationSplitViewColumnWidth(190)
        .toolbar(removing: .sidebarToggle)
      } detail: {
        paneContent(for: selectedPane ?? .general)
      }
      .frame(
        minWidth: 640,
        idealWidth: 680,
        maxWidth: 780,
        minHeight: 440,
        idealHeight: 520,
        maxHeight: 820
      )
    }
  #else
    private var stackLayout: some View {
      NavigationStack {
        List {
          ForEach(SettingsPane.allCases) { pane in
            NavigationLink(value: pane) {
              paneLabel(for: pane)
            }
          }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsPane.self) { pane in
          paneContent(for: pane)
        }
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              dismiss()
            }
          }
        }
      }
    }
  #endif

  // MARK: - Panes

  private func paneLabel(for pane: SettingsPane) -> some View {
    Label {
      Text(pane.title)
    } icon: {
      SettingsPaneBadge(pane: pane)
    }
    .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.id))
  }

  @ViewBuilder
  func paneContent(for pane: SettingsPane) -> some View {
    Group {
      switch pane {
      case .general:
        GeneralSettingsView()
      case .storage:
        StorageSettingsView()
      case .credits:
        CreditsView()
      case .about:
        AboutView()
      }
    }
    .formStyle(.grouped)
    .tint(Color.botanicalDeepMoss)
    .navigationTitle(pane.title)
  }
}

/// A small colored squircle with a white SF Symbol, matching System Settings sidebar icons.
struct SettingsPaneBadge: View {
  let pane: SettingsPane

  var body: some View {
    Image(systemName: pane.systemImage)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(pane.badgeColor, in: .rect(cornerRadius: 5, style: .continuous))
  }
}
