//
//  SettingsPages.swift
//  Saga
//

import DylUI
import SwiftUI

extension SettingsPage {
  /// Saga's Settings, shown by DylUI's `SettingsWindow` on macOS and `SettingsView` in a sheet on iOS.
  @MainActor static var saga: [SettingsPage] {
    [
      SettingsPage("General", systemImage: "gearshape") { GeneralSettingsView() },
      SettingsPage("Storage", systemImage: "internaldrive") { StorageSettingsView() },
      SettingsPage("Credits", systemImage: "heart") { CreditsView() },
      SettingsPage("About", systemImage: "info.circle") { AboutView() },
    ]
  }
}
