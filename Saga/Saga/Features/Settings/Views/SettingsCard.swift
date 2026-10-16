//
//  SettingsCard.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// A Luminare-inspired Liquid Glass card container that groups related settings rows.
struct SettingsCard<Content: View>: View {
  let title: String?
  let subtitle: String?
  let systemImage: String?
  let content: Content

  private let cornerRadius: CGFloat = 14

  init(
    title: String? = nil,
    subtitle: String? = nil,
    systemImage: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if title != nil || subtitle != nil {
        headerView
      }

      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(Color.botanicalCardFill)
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.botanicalCardBorder, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
  }

  private var headerView: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let title {
        HStack(spacing: 6) {
          if let systemImage {
            Image(systemName: systemImage)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.botanicalLeaf)
          }
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
        }
      }
      if let subtitle {
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 4)
  }
}

/// A hairline divider between rows inside a `SettingsCard`.
struct SettingsCardDivider: View {
  var body: some View {
    Divider()
      .opacity(0.65)
      .padding(.horizontal, 14)
  }
}
