//
//  SettingsPane.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Represents a top-level section in the Settings window/sheet.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
  case general
  case storage
  case credits
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general:
      "General"
    case .storage:
      "Storage"
    case .credits:
      "Credits"
    case .about:
      "About"
    }
  }

  var systemImage: String {
    switch self {
    case .general:
      "gearshape.fill"
    case .storage:
      "internaldrive.fill"
    case .credits:
      "heart.fill"
    case .about:
      "info.circle.fill"
    }
  }

  /// Muted earth-tone fill for the sidebar squircle badge.
  var badgeColor: Color {
    switch self {
    case .general:
      Color(red: 0.369, green: 0.455, blue: 0.408)
    case .storage:
      Color(red: 0.357, green: 0.478, blue: 0.549)
    case .credits:
      Color(red: 0.753, green: 0.541, blue: 0.243)
    case .about:
      Color(red: 0.706, green: 0.392, blue: 0.290)
    }
  }
}
