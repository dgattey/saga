//
//  AppAnimation.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

enum AppAnimation {
  static let selectionSpringResponse: Double = 0.3
  static let selectionSpringDamping: Double = 0.65
  static let selectionSpring = Animation.spring(
    response: selectionSpringResponse,
    dampingFraction: selectionSpringDamping
  )

  static func coverRotationDegrees(
    from hash: Int,
    minDegrees: Double,
    maxDegrees: Double
  ) -> Double {
    let normalizedHash = abs(hash)
    let range = maxDegrees - minDegrees
    return minDegrees + (Double(normalizedHash % 10000) / 10000.0) * range
  }
}
