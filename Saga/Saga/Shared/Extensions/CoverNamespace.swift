//
//  CoverNamespace.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

private struct CoverNamespaceKey: EnvironmentKey {
  static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
  var coverNamespace: Namespace.ID? {
    get { self[CoverNamespaceKey.self] }
    set { self[CoverNamespaceKey.self] = newValue }
  }
}
