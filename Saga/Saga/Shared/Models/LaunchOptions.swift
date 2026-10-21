//
//  LaunchOptions.swift
//  Saga
//

import Foundation
import SwiftUI

/// Launch flags for screenshots and agent runs (`scripts/ui-screenshots.sh`). Each option reads
/// the environment variable `SAGA_<NAME>` first, then the argument `--<name> <value>`. A normal
/// launch sets neither, so every option is nil.
enum LaunchOptions {
  enum InitialView: String {
    case home
    /// Opens the book the sidebar's Now Reading card shows, else the first book in the sidebar.
    case book
  }

  static let initialView = value("initial-view").flatMap(InitialView.init(rawValue:))

  static let colorScheme: ColorScheme? =
    switch value("appearance") {
    case "light": .light
    case "dark": .dark
    default: nil
    }

  private static func value(_ name: String) -> String? {
    let variable = "SAGA_" + name.uppercased().replacingOccurrences(of: "-", with: "_")
    if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty {
      return value.lowercased()
    }
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--\(name)"), arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1].lowercased()
  }
}
