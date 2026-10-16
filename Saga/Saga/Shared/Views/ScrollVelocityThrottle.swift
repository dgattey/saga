//
//  ScrollVelocityThrottle.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import QuartzCore
import SwiftUI

struct ScrollVelocityReader: View {
  var body: some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: ScrollVelocityPreferenceKey.self,
        value: proxy.frame(in: .named(ScrollVelocityThrottle.coordinateSpaceName)).minY
      )
    }
    .frame(height: 0)
  }
}

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

private struct ScrollVelocityPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = .zero
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
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
  static let coordinateSpaceName = "scroll-velocity"

  let velocityThreshold: CGFloat
  let pauseReleaseDelay: Duration

  @State private var state = ThrottleState()

  func body(content: Content) -> some View {
    content
      .coordinateSpace(name: Self.coordinateSpaceName)
      .onPreferenceChange(ScrollVelocityPreferenceKey.self) { newOffset in
        let now = CACurrentMediaTime()
        guard state.lastTimestamp > 0 else {
          state.lastTimestamp = now
          state.lastOffset = newOffset
          return
        }
        let delta = abs(newOffset - state.lastOffset)
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
        state.lastOffset = newOffset
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
