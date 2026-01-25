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

private struct ScrollVelocityThrottle: ViewModifier {
  static let coordinateSpaceName = "scroll-velocity"

  let velocityThreshold: CGFloat
  let pauseReleaseDelay: Duration

  @State private var lastOffset: CGFloat = .zero
  @State private var lastTimestamp: CFTimeInterval = 0
  @State private var isPaused = false
  @State private var resumeTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      .coordinateSpace(name: Self.coordinateSpaceName)
      .onPreferenceChange(ScrollVelocityPreferenceKey.self) { newOffset in
        let now = CACurrentMediaTime()
        guard lastTimestamp > 0 else {
          lastTimestamp = now
          lastOffset = newOffset
          return
        }
        let delta = abs(newOffset - lastOffset)
        let dt = now - lastTimestamp
        if dt > 0 {
          let velocity = delta / dt
          if velocity >= velocityThreshold {
            if !isPaused {
              isPaused = true
              ImageCache.setDownloadsPaused(true)
            }
            resumeTask?.cancel()
            resumeTask = Task { @MainActor in
              try? await Task.sleep(for: pauseReleaseDelay)
              guard !Task.isCancelled else { return }
              isPaused = false
              ImageCache.setDownloadsPaused(false)
            }
          }
        }
        lastOffset = newOffset
        lastTimestamp = now
      }
      .onDisappear {
        resumeTask?.cancel()
        if isPaused {
          isPaused = false
          ImageCache.setDownloadsPaused(false)
        }
      }
  }
}
