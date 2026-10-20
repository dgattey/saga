//
//  NewBookAction.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI

/// Opens the New Book editor in the focused window. Published with `focusedSceneValue` so
/// File > New Book… targets the right window.
struct NewBookAction {
  private let action: () -> Void

  init(_ action: @escaping () -> Void) {
    self.action = action
  }

  func callAsFunction() {
    action()
  }
}

extension FocusedValues {
  @Entry var newBookAction: NewBookAction?
}
