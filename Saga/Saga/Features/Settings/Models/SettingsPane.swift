//
//  SettingsPane.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
  case storage
  case interface
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .storage:
      "Data & Storage"
    case .interface:
      "Interface"
    case .about:
      "About"
    }
  }

  var systemImage: String {
    switch self {
    case .storage:
      "internaldrive"
    case .interface:
      "slider.horizontal.3"
    case .about:
      "info.circle"
    }
  }

  /// Muted botanical-palette fill used for the sidebar squircle badge.
  var badgeColor: Color {
    switch self {
    case .storage:
      Color(red: 0.357, green: 0.478, blue: 0.549)  // slate #5B7A8C
    case .interface:
      Color(red: 0.369, green: 0.455, blue: 0.408)  // sage #5E7468
    case .about:
      Color(red: 0.706, green: 0.392, blue: 0.290)  // terracotta #B4644A
    }
  }

  /// Accent fill used for the Credits navigation link badge on iOS.
  static let creditsBadgeColor = Color(red: 0.753, green: 0.541, blue: 0.243)  // ochre #C08A3E
}
