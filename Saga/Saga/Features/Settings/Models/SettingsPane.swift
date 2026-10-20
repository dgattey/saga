//
//  SettingsPane.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

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
      "gearshape"
    case .storage:
      "internaldrive"
    case .credits:
      "heart"
    case .about:
      "info.circle"
    }
  }
}
