//
//  View+Styling.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

extension View {

  /// Our default shadow across the whole app
  func defaultShadow() -> some View {
    self.shadow(color: .black.opacity(0.1), radius: 8)
  }

  /// Randomly rotates a view based on some hash
  func randomRotation(
    from hash: Int,
    minDegrees: Double = -15,
    maxDegrees: Double = 15
  ) -> some View {
    let normalizedHash = abs(hash)  // Handle negative hashes
    let range = maxDegrees - minDegrees
    let rotation = minDegrees + (Double(normalizedHash % 10000) / 10000.0) * range

    return self.rotationEffect(.degrees(rotation))
  }
}
