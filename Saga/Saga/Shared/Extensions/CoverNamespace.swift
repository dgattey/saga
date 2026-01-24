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

private struct CoverMatchActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var coverNamespace: Namespace.ID? {
        get { self[CoverNamespaceKey.self] }
        set { self[CoverNamespaceKey.self] = newValue }
    }

    var coverMatchActive: Bool {
        get { self[CoverMatchActiveKey.self] }
        set { self[CoverMatchActiveKey.self] = newValue }
    }
}
