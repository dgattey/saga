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
  static let coverFadeResponse: Double = 0.4
  static let coverFadeDamping: Double = 1.0
  static let coverFade = Animation.spring(
    response: coverFadeResponse,
    dampingFraction: coverFadeDamping
  )
  static let coverRotationResponse: Double = selectionSpringResponse
  static let coverRotationDamping: Double = selectionSpringDamping
  static let coverRotation = Animation.spring(
    response: coverRotationResponse,
    dampingFraction: coverRotationDamping
  )
  static let coverMatchHoldDuration: Double = max(
    selectionSpringResponse,
    max(coverFadeResponse, coverRotationResponse)
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
