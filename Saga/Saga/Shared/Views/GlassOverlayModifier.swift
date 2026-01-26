//
//  GlassOverlayModifier.swift
//  Saga
//
//  Created by Dylan Gattey on 1/26/26.
//

import SwiftUI

/// Configuration for the glass overlay effect
struct GlassOverlayConfiguration {
  /// The edge where the overlay appears and is solid
  let edge: VerticalEdge

  /// The height of the glass overlay (only used for overlay modifier, not background)
  let height: CGFloat

  /// Default configuration for top edge (header-style)
  static let top = GlassOverlayConfiguration(edge: .top, height: 140)

  /// Default configuration for bottom edge (footer-style)
  static let bottom = GlassOverlayConfiguration(edge: .bottom, height: 100)
}

/// A reusable glass blur background view with gradient fade
/// Use as a background for views that need the blur effect
struct GlassBackgroundView: View {
  let edge: VerticalEdge

  init(edge: VerticalEdge = .top) {
    self.edge = edge
  }

  var body: some View {
    Rectangle()
      .fill(.ultraThinMaterial)
      .mask(gradientMask)
      .allowsHitTesting(false)
  }

  private var gradientMask: some View {
    LinearGradient(
      stops: [
        .init(color: .black, location: 0.0),
        .init(color: .black.opacity(0.75), location: 0.75),
        .init(color: .clear, location: 1.0),
      ],
      startPoint: startPoint,
      endPoint: endPoint
    )
  }

  private var startPoint: UnitPoint {
    switch edge {
    case .top: .top
    case .bottom: .bottom
    }
  }

  private var endPoint: UnitPoint {
    switch edge {
    case .top: .bottom
    case .bottom: .top
    }
  }
}

/// A view modifier that adds a glass blur overlay effect with gradient fade
private struct GlassOverlayModifier: ViewModifier {
  let configuration: GlassOverlayConfiguration

  func body(content: Content) -> some View {
    ZStack(alignment: alignment) {
      content
        .zIndex(0)
      glassOverlayView
        .zIndex(1)
    }
  }

  private var alignment: Alignment {
    switch configuration.edge {
    case .top: .top
    case .bottom: .bottom
    }
  }

  private var edgeSet: Edge.Set {
    switch configuration.edge {
    case .top: .top
    case .bottom: .bottom
    }
  }

  private var glassOverlayView: some View {
    GlassBackgroundView(edge: configuration.edge)
      .frame(height: configuration.height)
      .frame(maxWidth: .infinity, alignment: alignment)
      .ignoresSafeArea(.container, edges: edgeSet)
  }
}

extension View {
  /// Adds a glass overlay effect that fades from a specified edge
  /// - Parameter configuration: The configuration for the glass overlay
  /// - Returns: A view with the glass overlay applied
  func withGlassOverlay(_ configuration: GlassOverlayConfiguration = .top) -> some View {
    modifier(GlassOverlayModifier(configuration: configuration))
  }

  /// Adds a glass overlay effect at the top edge (for headers)
  /// - Parameter height: The height of the overlay (defaults to 140)
  /// - Returns: A view with the glass overlay applied
  func withGlassOverlay(height: CGFloat) -> some View {
    modifier(
      GlassOverlayModifier(configuration: GlassOverlayConfiguration(edge: .top, height: height)))
  }

  /// Adds a glass overlay effect at a specified edge with custom height
  /// - Parameters:
  ///   - edge: The edge where the overlay appears
  ///   - height: The height of the overlay
  /// - Returns: A view with the glass overlay applied
  func withGlassOverlay(edge: VerticalEdge, height: CGFloat) -> some View {
    modifier(
      GlassOverlayModifier(configuration: GlassOverlayConfiguration(edge: edge, height: height)))
  }

  /// Adds a glass background effect that fades from a specified edge
  /// Use this when the view needs a background blur (like in safeAreaInset)
  /// - Parameter edge: The edge where the glass is solid (fades toward opposite edge)
  /// - Returns: A view with the glass background applied
  func withGlassBackground(edge: VerticalEdge = .top) -> some View {
    background(
      GlassBackgroundView(edge: edge)
        .ignoresSafeArea(.container, edges: edge == .top ? .top : .bottom)
    )
  }
}
