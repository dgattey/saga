//
//  View+Styling.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

extension View {

  /// Applies the standard window background effect to any view.
  /// Use this on the root view of every Scene for consistent styling.
  func windowBackground() -> some View {
    #if os(macOS)
      self.containerBackground(for: .window) {
        ZStack {
          Rectangle().fill(.ultraThinMaterial)
          Color.botanicalSurfaceTint.opacity(0.45)
        }
      }
    #else
      self
        .scrollContentBackground(.hidden)
        .background(Color.botanicalBackground.ignoresSafeArea())
        .containerBackground(for: .navigationSplitView) {
          ZStack {
            Color.botanicalBackground
            Rectangle().fill(.ultraThinMaterial)
            Color.botanicalSurfaceTint.opacity(0.65)
          }
        }
    #endif
  }

  /// Applies the shared botanical surface background on iOS while letting macOS
  /// use its translucent window container background.
  func botanicalPageBackground() -> some View {
    #if os(iOS)
      self
        .scrollContentBackground(.hidden)
        .background {
          ZStack {
            Color.botanicalBackground
            Rectangle().fill(.ultraThinMaterial)
            Color.botanicalSurfaceTint.opacity(0.65)
          }
          .ignoresSafeArea()
        }
    #else
      self
    #endif
  }

  /// Layered contact, key, and ambient shadows so a book cover reads as a physical object
  /// resting on the page.
  func physicalCoverShadow() -> some View {
    self
      .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
      .shadow(color: .black.opacity(0.14), radius: 4, y: 4)
      .shadow(color: .black.opacity(0.20), radius: 14, y: 14)
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
