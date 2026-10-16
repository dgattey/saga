//
//  CreditsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Displays Saga's About header, Data & API attributions, and Open Source library acknowledgements.
struct CreditsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard {
        AppInformationView()
      }

      SettingsCard(
        title: "Data & APIs",
        subtitle: "Book metadata, cover art resolution, and cloud sync services",
        systemImage: "network"
      ) {
        ForEach(Array(CreditItem.dataAndAPIs.enumerated()), id: \.element.id) { index, item in
          if index > 0 {
            SettingsCardDivider()
          }
          CreditRowView(item: item)
        }
      }

      SettingsCard(
        title: "Open Source Libraries",
        subtitle: "Saga is built on these open source Swift packages and tools",
        systemImage: "chevron.left.forwardslash.chevron.right"
      ) {
        ForEach(Array(CreditItem.openSourceLibraries.enumerated()), id: \.element.id) {
          index, item in
          if index > 0 {
            SettingsCardDivider()
          }
          CreditRowView(item: item)
        }
      }
    }
    .accessibilityIdentifier(AccessibilityID.Settings.creditsView)
  }
}

/// A single Luminare-style attribution row with icon badge, version pill, role subtitle, and links.
struct CreditRowView: View {
  let item: CreditItem
  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 12) {
      iconBadge

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Link(destination: item.url) {
            Text(item.name)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          #if os(macOS)
            .pointerStyle(.link)
          #endif

          if let version = item.version {
            Text(version == "Debug" ? version : "v\(version)")
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule().fill(.quaternary.opacity(0.6)))
          }
        }

        Text(item.subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      HStack(spacing: 6) {
        badgeView

        Link(destination: item.url) {
          Image(systemName: "arrow.up.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(
              Circle()
                .fill(.quaternary.opacity(isHovering ? 0.9 : 0.45))
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
          .pointerStyle(.link)
        #endif
        .accessibilityLabel("Open \(item.name)")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      if isHovering {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.botanicalLeaf.opacity(0.06))
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.15)) {
        isHovering = hovering
      }
    }
  }

  private var iconBadge: some View {
    Image(systemName: item.systemImage)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(item.tintColor)
      .frame(width: 32, height: 32)
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(item.tintColor.opacity(0.14))
      }
      .glassEffect(
        .regular.tint(item.tintColor.opacity(0.12)),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
  }

  @ViewBuilder
  private var badgeView: some View {
    if let badgeURL = item.badgeURL {
      Link(destination: badgeURL) {
        badgeLabel
      }
      .buttonStyle(.plain)
      #if os(macOS)
        .pointerStyle(.link)
      #endif
    } else {
      badgeLabel
    }
  }

  private var badgeLabel: some View {
    Text(item.badge)
      .font(.caption2.monospaced().weight(.medium))
      .foregroundStyle(Color.botanicalLeaf)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .glassEffect(
        .regular.tint(Color.botanicalLeaf.opacity(0.09)),
        in: Capsule()
      )
  }
}
