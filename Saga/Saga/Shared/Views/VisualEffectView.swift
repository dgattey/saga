//
//  VisualEffectView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/23/26.
//

import SwiftUI

#if os(macOS)
  import AppKit
#endif

private enum VisualEffectDefaults {
  static let gradientStops: [CGFloat] = [0.0, 0.6, 1.0]
  static let gradientAlphas: [CGFloat] = [1.0, 0.9, 0.0]
}

#if os(macOS)
  struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
      let view = NSVisualEffectView()

      view.blendingMode = .behindWindow
      view.state = .active
      view.material = .underWindowBackground

      return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
  }

  final class MaskedVisualEffectContainer: NSView {
    let effectView = NSVisualEffectView()
    let maskLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true

      effectView.blendingMode = .behindWindow
      effectView.state = .active
      effectView.material = .underWindowBackground
      effectView.wantsLayer = true
      effectView.autoresizingMask = [.width, .height]
      addSubview(effectView)

      maskLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
      maskLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
      effectView.layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) {
      nil
    }

    override func layout() {
      super.layout()
      effectView.frame = bounds
      maskLayer.frame = effectView.bounds
    }
  }

  struct MaskedVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var gradientStops: [CGFloat] = VisualEffectDefaults.gradientStops
    var gradientAlphas: [CGFloat] = VisualEffectDefaults.gradientAlphas

    func makeNSView(context: Context) -> MaskedVisualEffectContainer {
      let container = MaskedVisualEffectContainer()
      apply(to: container)
      return container
    }

    func updateNSView(_ nsView: MaskedVisualEffectContainer, context: Context) {
      apply(to: nsView)
    }

    private func apply(to container: MaskedVisualEffectContainer) {
      container.effectView.material = material
      container.effectView.blendingMode = blendingMode
      container.effectView.state = state
      container.maskLayer.locations = gradientStops as [NSNumber]
      container.maskLayer.colors = gradientAlphas.map {
        NSColor.white.withAlphaComponent($0).cgColor
      }
    }
  }

#else
  // Fallback SwiftUI-only implementation for platforms without AppKit.
  // Uses system materials and a gradient mask to mimic the macOS visual effect.
  struct VisualEffectView: View {
    var material: Material = .ultraThinMaterial
    var body: some View {
      Rectangle().fill(material)
    }
  }

  private struct GradientMask: View {
    var stops: [CGFloat]
    var alphas: [CGFloat]

    var body: some View {
      LinearGradient(
        stops: zip(stops.indices, stops).map { idx, location in
          let alpha = alphas.indices.contains(idx) ? alphas[idx] : 1.0
          return .init(color: Color.white.opacity(Double(alpha)), location: location)
        },
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  extension View {
    fileprivate func masked(with stops: [CGFloat], alphas: [CGFloat]) -> some View {
      mask(GradientMask(stops: stops, alphas: alphas))
    }
  }

  struct MaskedVisualEffectView: View {
    var material: Material = .ultraThinMaterial
    var gradientStops: [CGFloat] = VisualEffectDefaults.gradientStops
    var gradientAlphas: [CGFloat] = VisualEffectDefaults.gradientAlphas

    var body: some View {
      VisualEffectView(material: material)
        .masked(with: gradientStops, alphas: gradientAlphas)
    }
  }

#endif

// MARK: - Window Background Modifier
struct WindowBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(VisualEffectView().ignoresSafeArea())
  }
}

extension View {
  /// Applies the standard window background effect to any view.
  /// Use this on the root view of every Scene for consistent styling.
  func windowBackground() -> some View {
    modifier(WindowBackgroundModifier())
  }
}
