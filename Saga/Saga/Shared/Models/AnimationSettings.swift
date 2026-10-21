//
//  AnimationSettings.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

/// Observable animation settings that persist to UserDefaults and update live
@Observable
final class AnimationSettings {
  /// Shared instance for access outside of SwiftUI views
  static let shared = AnimationSettings()

  // Default values
  static let defaultSpringResponse: Double = 0.3
  static let defaultSpringDamping: Double = 0.7

  // Storage keys
  private static let springResponseKey = "animation.springResponse"
  private static let springDampingKey = "animation.springDamping"

  var springResponse: Double {
    didSet { UserDefaults.standard.set(springResponse, forKey: Self.springResponseKey) }
  }
  var springDamping: Double {
    didSet { UserDefaults.standard.set(springDamping, forKey: Self.springDampingKey) }
  }

  init() {
    let defaults = UserDefaults.standard
    springResponse =
      defaults.object(forKey: Self.springResponseKey) as? Double ?? Self.defaultSpringResponse
    springDamping =
      defaults.object(forKey: Self.springDampingKey) as? Double ?? Self.defaultSpringDamping
  }

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
