//
//  ScrollPositionStore.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

@MainActor
final class ScrollPositionStore: ObservableObject {
  @Published private(set) var resetToken = UUID()
  @Published private(set) var scrollToTopToken = UUID()
  @Published private(set) var scrollToTopScope: ScrollScope?
  private var positions: [ScrollKey: Double] = [:]

  func position(for key: ScrollKey) -> Double? {
    positions[key]
  }

  func update(_ position: Double, for key: ScrollKey) {
    let clamped = max(0, position)
    guard positions[key] != clamped else { return }
    positions[key] = clamped
  }

  func clonePositions(from sourceContextID: UUID, to targetContextID: UUID, scope: ScrollScope) {
    let matches = positions.filter { key, _ in
      key.scope == scope && key.contextID == sourceContextID
    }
    guard !matches.isEmpty else { return }
    for (key, value) in matches {
      let targetKey = ScrollKey(
        scope: key.scope,
        region: key.region,
        contextID: targetContextID
      )
      positions[targetKey] = value
    }
  }

  /// Scrolls a specific scope to the top immediately (without animation)
  func scrollToTop(for scope: ScrollScope) {
    // Clear stored positions for this scope
    positions = positions.filter { key, _ in key.scope != scope }
    scrollToTopScope = scope
    scrollToTopToken = UUID()
  }

  func reset() {
    positions.removeAll()
    resetToken = UUID()
  }
}
