//
//  CreditsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Data source and open source attributions as grouped form sections.
struct CreditsView: View {
  var body: some View {
    Form {
      Section("Data") {
        ForEach(CreditItem.dataAndAPIs) { item in
          CreditRowView(item: item)
        }
      }
      Section("Open Source") {
        ForEach(CreditItem.openSourceLibraries) { item in
          CreditRowView(item: item)
        }
      }
    }
    .accessibilityIdentifier(AccessibilityID.Settings.creditsView)
  }
}

/// A single attribution row: name, version and role on the left, license badge and link on the
/// right.
struct CreditRowView: View {
  let item: CreditItem

  var body: some View {
    LabeledContent {
      HStack(spacing: 10) {
        badge
        Link(destination: item.url) {
          Image(systemName: "arrow.up.right")
            .font(.caption.weight(.semibold))
        }
        .accessibilityLabel("Open \(item.name)")
        #if os(macOS)
          .pointerStyle(.link)
        #endif
      }
    } label: {
      Label {
        Text(title)
        Text(item.subtitle)
      } icon: {
        Image(systemName: item.systemImage)
          .foregroundStyle(item.tintColor)
      }
    }
  }

  private var title: String {
    guard let version = item.version else {
      return item.name
    }
    return version == "Debug" ? "\(item.name) · Debug" : "\(item.name) · v\(version)"
  }

  @ViewBuilder
  private var badge: some View {
    if let badgeURL = item.badgeURL {
      Link(item.badge, destination: badgeURL)
        .font(.callout.monospaced())
        #if os(macOS)
          .pointerStyle(.link)
        #endif
    } else {
      Text(item.badge)
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
    }
  }
}
