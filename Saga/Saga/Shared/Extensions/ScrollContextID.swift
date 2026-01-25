//
//  ScrollContextID.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

private struct ScrollContextIDKey: EnvironmentKey {
  static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
  var scrollContextID: UUID? {
    get { self[ScrollContextIDKey.self] }
    set { self[ScrollContextIDKey.self] = newValue }
  }
}
