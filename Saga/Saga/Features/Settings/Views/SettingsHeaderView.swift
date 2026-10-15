//
//  SettingsHeaderView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

struct SettingsHeaderView: View {
  let title: String
  let subtitle: String?
  let systemImage: String
  let backgroundColor: Color

  private let iconSize: CGFloat = 32
  private var cornerRadius: CGFloat { iconSize * 0.34 }

  init(
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    backgroundColor: Color
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.backgroundColor = backgroundColor
  }

  var body: some View {
    HStack(spacing: 12) {
      icon
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.title2.weight(.bold))
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 12)
  }

  private var icon: some View {
    Image(systemName: systemImage)
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: iconSize, height: iconSize)
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(backgroundColor.gradient)
      }
      .glassEffect(
        .regular.tint(backgroundColor),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
  }
}
