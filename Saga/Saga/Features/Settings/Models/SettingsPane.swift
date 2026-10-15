//
//  SettingsPane.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Represents a top-level section in the Settings window/sheet.
enum SettingsPane: String, CaseIterable, Identifiable {
  case general
  case storage
  case credits

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general:
      "General"
    case .storage:
      "Storage"
    case .credits:
      "Credits & About"
    }
  }

  var shortTitle: String {
    switch self {
    case .general:
      "General"
    case .storage:
      "Storage"
    case .credits:
      "Credits"
    }
  }

  var subtitle: String {
    switch self {
    case .general:
      #if os(macOS)
        "Software updates & spring animations"
      #else
        "Interactive spring animation tuning"
      #endif
    case .storage:
      "Disk caches & local Core Data storage"
    case .credits:
      "About Saga, data sources & open source"
    }
  }

  var systemImage: String {
    switch self {
    case .general:
      "slider.horizontal.3"
    case .storage:
      "internaldrive.fill"
    case .credits:
      "sparkles"
    }
  }

  var accentColor: Color {
    switch self {
    case .general:
      .botanicalLeaf
    case .storage:
      .botanicalMoss
    case .credits:
      .botanicalGold
    }
  }
}
