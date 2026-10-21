//
//  LaunchOverrides+Saga.swift
//  Saga
//

import DylCore

extension LaunchOverrides {
  /// `SAGA_<NAME>` / `--<name>` launch flags for screenshots and agent runs (`./run ui`, `devkit`).
  static let saga = LaunchOverrides(prefix: "SAGA")

  enum InitialView: String {
    case home
    /// Opens the book the sidebar's Now Reading card shows, else the first book in the sidebar.
    case book
  }

  var sagaInitialView: InitialView? { initialView.flatMap(InitialView.init(rawValue:)) }
}
