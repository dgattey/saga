//
//  SettingsSidebarView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Luminare-inspired sidebar column for navigating between Settings panes.
struct SettingsSidebarView: View {
  #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
  #endif
  @EnvironmentObject private var animationSettings: AnimationSettings
  @Binding var selectedPane: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("SETTINGS")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 4)

      ForEach(SettingsPane.allCases) { pane in
        sidebarRow(for: pane)
      }

      Spacer(minLength: 12)

      footerButton
    }
    .padding(.horizontal, 10)
    .padding(.bottom, 12)
    .frame(width: 205, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Color.botanicalSurfaceTint.opacity(0.18))
    .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
  }

  private func sidebarRow(for pane: SettingsPane) -> some View {
    let isSelected = selectedPane == pane

    return Button {
      withAnimation(animationSettings.selectionSpring) {
        selectedPane = pane
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: pane.systemImage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? .white : pane.accentColor)
          .frame(width: 26, height: 26)
          .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(isSelected ? pane.accentColor : pane.accentColor.opacity(0.14))
          }

        VStack(alignment: .leading, spacing: 1) {
          Text(pane.title)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(.primary)
          Text(pane.shortSubtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 0)
      }
      .padding(.vertical, 7)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(selectionBackgroundColor)
          .glassEffect(
            .regular.tint(selectionBackgroundColor).interactive(),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
      }
    }
    .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.id))
  }

  private var footerButton: some View {
    Button {
      withAnimation(animationSettings.selectionSpring) {
        selectedPane = .credits
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "leaf.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.botanicalLeaf)
        VStack(alignment: .leading, spacing: 1) {
          Text("Saga")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
          Text("v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "info.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.quinary.opacity(0.5))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.quaternary, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      return Color.sidebarSelectionFill(isActiveWindow: controlActiveState != .inactive)
    #else
      return Color.sidebarSelectionFill(isActiveWindow: true)
    #endif
  }
}

extension SettingsPane {
  fileprivate var shortSubtitle: String {
    switch self {
    case .general:
      #if os(macOS)
        "Updates & animations"
      #else
        "Spring animations"
      #endif
    case .storage:
      "Caches & local data"
    case .credits:
      "About & open source"
    }
  }
}
