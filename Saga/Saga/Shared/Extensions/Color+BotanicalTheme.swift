//
//  Color+BotanicalTheme.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

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

  static var botanicalSurfaceTint: Color {
    adaptiveColor(
      light: (0.935, 0.955, 0.945),
      dark: (0.065, 0.110, 0.088)
    )
  }

  static func sidebarSelectionFill(isActiveWindow: Bool = true) -> Color {
    if isActiveWindow {
      return adaptiveColor(
        light: (0.149, 0.306, 0.227, 0.18),
        dark: (0.220, 0.415, 0.328, 0.26)
      )
    }
    return adaptiveColor(
      light: (0.210, 0.330, 0.268, 0.10),
      dark: (0.235, 0.385, 0.315, 0.14)
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
