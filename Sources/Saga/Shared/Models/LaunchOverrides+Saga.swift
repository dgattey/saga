//
//  LaunchOverrides+Saga.swift
//  Saga
//

import DylCore
import Foundation

extension LaunchOverrides {
  enum InitialView: String {
    case home
    /// Opens the book the sidebar's Now Reading card shows, else the first book in the sidebar.
    case book
    /// Opens that book directly in the in-place editorial editor.
    case bookEdit = "book-edit"
    /// Presents the Settings sheet on launch.
    case settings
    /// Filters sidebar search to `.hasNotes` and optional `searchQuery`.
    case search
  }

  var sagaInitialView: InitialView? {
    (initialView ?? rawOption("initial-view")?.lowercased()).flatMap(InitialView.init(rawValue:))
  }
  var settingsPane: SettingsPane? {
    (value("settings-pane") ?? rawOption("settings-pane")?.lowercased())
      .flatMap(SettingsPane.init(rawValue:))
  }
  var searchQuery: String? { rawOption("search-query") ?? value("search-query") }
  var storePath: String? { rawOption("store-path") ?? value("store-path") }
  var scrollSidebarToBottom: Bool {
    flag("scroll-sidebar-bottom")
      || ["1", "true", "yes"].contains(
        ProcessInfo.processInfo.environment["SAGA_SCROLL_SIDEBAR_BOTTOM"]?.lowercased() ?? ""
      )
  }

  private func rawOption(_ name: String) -> String? {
    let suffix = name.uppercased().replacingOccurrences(of: "-", with: "_")
    let env = ProcessInfo.processInfo.environment
    for prefix in ["DYLKIT_", "SAGA_"] {
      if let value = env[prefix + suffix]?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
        return value
      }
    }
    let arguments = ProcessInfo.processInfo.arguments
    let flag = "--\(name)"
    for (index, argument) in arguments.enumerated() {
      let lowered = argument.lowercased()
      if lowered.hasPrefix("\(flag)=") {
        return String(argument.dropFirst(flag.count + 1))
      }
      if lowered == flag, arguments.indices.contains(index + 1),
        !arguments[index + 1].hasPrefix("--")
      {
        return arguments[index + 1]
      }
    }
    return nil
  }
}
