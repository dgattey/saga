//
//  AnimationSettings.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

/// Observable animation settings that persist to UserDefaults and update live
final class AnimationSettings: ObservableObject {
  /// Shared instance for access outside of SwiftUI views
  static let shared = AnimationSettings()

  // Default values
  static let defaultSpringResponse: Double = 0.3
  static let defaultSpringDamping: Double = 0.7

  // Storage keys
  private static let springResponseKey = "animation.springResponse"
  private static let springDampingKey = "animation.springDamping"

  @AppStorage(springResponseKey) var springResponse: Double = defaultSpringResponse
  @AppStorage(springDampingKey) var springDamping: Double = defaultSpringDamping

  /// The selection spring animation using current settings
  var selectionSpring: Animation {
    .spring(response: springResponse, dampingFraction: springDamping)
  }

  /// Resets animation values to defaults
  func resetToDefaults() {
    springResponse = Self.defaultSpringResponse
    springDamping = Self.defaultSpringDamping
  }
}
