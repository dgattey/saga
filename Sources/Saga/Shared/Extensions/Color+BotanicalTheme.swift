//
//  Color+BotanicalTheme.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import DylUI
import SwiftUI

#if os(macOS)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

extension Color {
  static var botanicalLeaf: Color {
    adaptiveColor(
      light: (0.149, 0.306, 0.227),
      dark: (0.290, 0.495, 0.395)
    )
  }

  static var botanicalForest: Color {
    adaptiveColor(
      light: (0.106, 0.231, 0.169),
      dark: (0.175, 0.345, 0.268)
    )
  }

  static var botanicalSage: Color {
    adaptiveColor(
      light: (0.245, 0.415, 0.340),
      dark: (0.420, 0.595, 0.505)
    )
  }

  static var botanicalMoss: Color {
    adaptiveColor(
      light: (0.200, 0.360, 0.290),
      dark: (0.345, 0.525, 0.440)
    )
  }

  static var botanicalGold: Color {
    adaptiveColor(
      light: (0.76, 0.55, 0.16),
      dark: (0.91, 0.73, 0.33)
    )
  }

  static var botanicalTerracotta: Color {
    adaptiveColor(
      light: (0.68, 0.36, 0.26),
      dark: (0.86, 0.54, 0.43)
    )
  }

  static var botanicalBackground: Color {
    adaptiveColor(
      light: (0.915, 0.945, 0.928),
      dark: (0.055, 0.105, 0.082)
    )
  }

  static var botanicalSurfaceTint: Color {
    adaptiveColor(
      light: (0.915, 0.945, 0.928),
      dark: (0.065, 0.115, 0.090)
    )
  }

  /// Crisp frosted surface tint for the floating "Currently reading" bar.
  static var nowReadingBarFill: Color {
    adaptiveColor(
      light: (0.992, 0.996, 0.993, 0.88),
      dark: (0.125, 0.175, 0.148, 0.86)
    )
  }

  /// Subtle hairline border for the floating "Currently reading" bar.
  static var nowReadingBarBorder: Color {
    adaptiveColor(
      light: (0.100, 0.200, 0.150, 0.12),
      dark: (0.850, 0.940, 0.890, 0.15)
    )
  }

  /// High-contrast botanical accent for the "Currently reading" eyebrow label and glyph.
  static var nowReadingAccent: Color {
    adaptiveColor(
      light: (0.149, 0.306, 0.227),
      dark: (0.490, 0.745, 0.605)
    )
  }

  /// Opaque surface fill for book cover placeholders so elevation shadows never bleed through.
  static var botanicalCoverPlaceholderFill: Color {
    adaptiveColor(
      light: (0.905, 0.932, 0.914, 1.0),
      dark: (0.195, 0.265, 0.228, 1.0)
    )
  }

  /// Subtle rim border for book cover placeholders.
  static var botanicalCoverPlaceholderBorder: Color {
    adaptiveColor(
      light: (0.120, 0.240, 0.180, 0.14),
      dark: (0.850, 0.950, 0.900, 0.14)
    )
  }

  /// Crisp icon color for book cover placeholders in both light and dark modes.
  static var botanicalCoverPlaceholderIcon: Color {
    adaptiveColor(
      light: (0.185, 0.345, 0.275),
      dark: (0.640, 0.800, 0.710)
    )
  }

  /// Muted olive-forest used for the sidebar Home badge.
  static var botanicalOlive: Color {
    adaptiveColor(
      light: (0.361, 0.431, 0.345),
      dark: (0.490, 0.561, 0.475)
    )
  }

  /// Warm cream glyph color for icons drawn on top of botanical badges.
  static var botanicalCream: Color {
    adaptiveColor(
      light: (0.961, 0.949, 0.902),
      dark: (0.961, 0.949, 0.902)
    )
  }

  /// Deep moss control tint for switches and sliders, chosen to avoid any emerald/neon green.
  static var botanicalDeepMoss: Color {
    adaptiveColor(
      light: (0.231, 0.353, 0.278),
      dark: (0.431, 0.549, 0.471)
    )
  }

  /// Warm stone selection pill: neutral like stock macOS selection, with no green in the fill.
  static func sidebarSelectionFill(isActiveWindow: Bool = true) -> Color {
    if isActiveWindow {
      return adaptiveColor(
        light: (0.282, 0.243, 0.188, 0.085),
        dark: (1.0, 0.965, 0.902, 0.10)
      )
    }
    return adaptiveColor(
      light: (0.282, 0.243, 0.188, 0.055),
      dark: (1.0, 0.965, 0.902, 0.065)
    )
  }

  private static func adaptiveColor(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat)
  ) -> Color {
    adaptiveColor(
      light: (light.0, light.1, light.2, 1.0),
      dark: (dark.0, dark.1, dark.2, 1.0)
    )
  }

  private static func adaptiveColor(
    light: (CGFloat, CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat, CGFloat)
  ) -> Color {
    #if os(macOS)
      return Color(
        nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          let components = isDark ? dark : light
          return NSColor(
            srgbRed: components.0,
            green: components.1,
            blue: components.2,
            alpha: components.3
          )
        }
      )
    #elseif canImport(UIKit)
      return Color(
        uiColor: UIColor { traitCollection in
          let isDark = traitCollection.userInterfaceStyle == .dark
          let components = isDark ? dark : light
          return UIColor(
            red: components.0,
            green: components.1,
            blue: components.2,
            alpha: components.3
          )
        }
      )
    #else
      return Color(
        .sRGB,
        red: light.0,
        green: light.1,
        blue: light.2,
        opacity: light.3
      )
    #endif
  }
}

/// DylUI's palette for Saga: the botanical accent (`AccentColor`) with sage hairlines and fills.
struct SagaPalette: ThemePalette {
  var accent: Color { .accentColor }
  var secondaryText: Color { .secondary }
  var subtleFill: Color { .botanicalSage.opacity(0.12) }
  var border: Color { .botanicalSage.opacity(0.25) }
}
