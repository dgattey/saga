//
//  SettingsHeaderView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

/// A reusable header view for settings-style screens with an icon and title.
struct SettingsHeaderView: View {
  let title: String
  let systemImage: String
  let backgroundColor: Color

  private let iconSize: CGFloat = 28
  private var cornerRadius: CGFloat { iconSize * 0.36 }

  var body: some View {
    HStack(spacing: 12) {
      icon
      Text(title)
        .font(.largeTitleBold)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .withGlassBackground(edge: .top)
  }

  private var icon: some View {
    Image(systemName: systemImage)
      .font(.system(size: 16, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: iconSize, height: iconSize)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(
            LinearGradient(
              colors: [.white.opacity(0.3), .clear],
              startPoint: .top,
              endPoint: .center
            )
          )
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}
