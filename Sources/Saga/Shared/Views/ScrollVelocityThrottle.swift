//
//  ScrollVelocityThrottle.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import QuartzCore
import SwiftUI

extension View {
  func scrollVelocityThrottle(
    velocityThreshold: CGFloat = 1200,
    pauseReleaseDelay: Duration = .milliseconds(200)
  ) -> some View {
    modifier(
      ScrollVelocityThrottle(
        velocityThreshold: velocityThreshold,
        pauseReleaseDelay: pauseReleaseDelay
      )
    )
  }
}

private final class ThrottleState {
  var lastOffset: CGFloat = .zero
  var lastTimestamp: CFTimeInterval = 0
  var isPaused = false
  var lastScheduleTimestamp: CFTimeInterval = 0
  var resumeTask: Task<Void, Never>?
}

private struct ScrollVelocityThrottle: ViewModifier {
  let velocityThreshold: CGFloat
  let pauseReleaseDelay: Duration

  @State private var state = ThrottleState()

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Int.self) { geometry in
        let rawOffset = geometry.contentOffset.y
        return rawOffset.isFinite ? Int(rawOffset.rounded()) : 0
      } action: { _, newOffset in
        let now = CACurrentMediaTime()
        let offset = CGFloat(newOffset)
        guard state.lastTimestamp > 0 else {
          state.lastTimestamp = now
          state.lastOffset = offset
          return
        }
        let delta = abs(offset - state.lastOffset)
        let dt = now - state.lastTimestamp
        if dt > 0 {
          let velocity = delta / dt
          if velocity >= velocityThreshold {
            if !state.isPaused {
              state.isPaused = true
              ImageCache.setDownloadsPaused(true)
            }
            if now - state.lastScheduleTimestamp >= 0.05 {
              state.lastScheduleTimestamp = now
              state.resumeTask?.cancel()
              let currentState = state
              let delay = pauseReleaseDelay
              state.resumeTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                currentState.isPaused = false
                ImageCache.setDownloadsPaused(false)
              }
            }
          }
        }
        state.lastOffset = offset
        state.lastTimestamp = now
      }
      .onDisappear {
        state.resumeTask?.cancel()
        if state.isPaused {
          state.isPaused = false
          ImageCache.setDownloadsPaused(false)
        }
      }
  }
}
