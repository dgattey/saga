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
  private var positions: [ScrollKey: Double] = [:]

  func position(for key: ScrollKey) -> Double? {
    positions[key]
  }

  func update(_ position: Double, for key: ScrollKey) {
    let clamped = max(0, position)
    guard positions[key] != clamped else { return }
    positions[key] = clamped
  }

  func reset() {
    positions.removeAll()
    resetToken = UUID()
  }
}
