//
//  SettingsPane.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// Sidebar category groupings for `SettingsPane`.
enum SettingsPaneSection: String, CaseIterable, Identifiable {
  case general
  case library
  case interface
  case app

  var id: String { rawValue }

  var title: String? {
    switch self {
    case .general:
      nil
    case .library:
      "Library"
    case .interface:
      "Interface"
    case .app:
      "App"
    }
  }

  var panes: [SettingsPane] {
    switch self {
    case .general:
      [.general]
    case .library:
      [.sync, .storage]
    case .interface:
      [.animations]
    case .app:
      [.credits, .about]
    }
  }
}

/// Represents a top-level page in the Settings window/sheet.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
  case general
  case sync
  case storage
  case animations
  case credits
  case about

  var id: String { rawValue }

  var section: SettingsPaneSection {
    switch self {
    case .general:
      .general
    case .sync, .storage:
      .library
    case .animations:
      .interface
    case .credits, .about:
      .app
    }
  }

  var title: String {
    switch self {
    case .general:
      "General"
    case .sync:
      "Sync"
    case .storage:
      "Storage"
    case .animations:
      "Animations"
    case .credits:
      "Credits"
    case .about:
      "About"
    }
  }

  var subtitle: String {
    switch self {
    case .general:
      "Automatic software updates and app preferences"
    case .sync:
      "Contentful and Goodreads library synchronization"
    case .storage:
      "Disk cache limits and local storage maintenance"
    case .animations:
      "Interactive spring physics and motion tuning"
    case .credits:
      "Data sources, APIs, and open source acknowledgements"
    case .about:
      "App version, author attribution, and quick links"
    }
  }

  var systemImage: String {
    switch self {
    case .general:
      "gearshape.fill"
    case .sync:
      "arrow.triangle.2.circlepath"
    case .storage:
      "internaldrive.fill"
    case .animations:
      "sparkles"
    case .credits:
      "heart.fill"
    case .about:
      "info.circle.fill"
    }
  }

  /// Distinct botanical-palette fill used for the sidebar and header squircle badges.
  var badgeColor: Color {
    switch self {
    case .general:
      Color(red: 0.455, green: 0.478, blue: 0.498)  // warm slate #747A7F
    case .sync:
      Color(red: 0.239, green: 0.518, blue: 0.380)  // botanical emerald #3D8461
    case .storage:
      Color(red: 0.255, green: 0.490, blue: 0.635)  // sky teal #417DA2
    case .animations:
      Color(red: 0.467, green: 0.396, blue: 0.682)  // botanical iris #7765AE
    case .credits:
      Color(red: 0.761, green: 0.533, blue: 0.243)  // warm ochre gold #C2883E
    case .about:
      Color(red: 0.706, green: 0.392, blue: 0.290)  // terracotta #B4644A
    }
  }
}
