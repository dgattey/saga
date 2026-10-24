//
//  SettingsHeaderView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

/// Tuneful-style pane header displayed in the detail pane's `.navigation` toolbar slot,
/// pairing a 25×25 colored rounded-square icon badge with a semibold title aligned with the traffic lights.
struct SettingsHeaderView: View {
  let title: String
  let systemImage: String
  let backgroundColor: Color

  init(pane: SettingsPane) {
    self.title = pane.title
    self.systemImage = pane.systemImage
    self.backgroundColor = pane.badgeColor
  }

  init(
    title: String,
    systemImage: String,
    backgroundColor: Color
  ) {
    self.title = title
    self.systemImage = systemImage
    self.backgroundColor = backgroundColor
  }

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      SettingsIconBadge(
        systemImage: systemImage,
        color: backgroundColor,
        size: 25
      )
      Text(title)
        .font(.title)
        .fontWeight(.semibold)
    }
    .padding(.horizontal, 13)
  }
}
