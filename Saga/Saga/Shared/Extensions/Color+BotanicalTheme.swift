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
      light: (0.21, 0.49, 0.30),
      dark: (0.40, 0.72, 0.49)
    )
  }

  static var botanicalForest: Color {
    adaptiveColor(
      light: (0.14, 0.34, 0.21),
      dark: (0.28, 0.56, 0.37)
    )
  }

  static var botanicalSage: Color {
    adaptiveColor(
      light: (0.35, 0.56, 0.42),
      dark: (0.54, 0.76, 0.60)
    )
  }

  static var botanicalMoss: Color {
    adaptiveColor(
      light: (0.39, 0.50, 0.25),
      dark: (0.62, 0.75, 0.44)
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
      light: (0.94, 0.96, 0.93),
      dark: (0.08, 0.13, 0.10)
    )
  }

  static func sidebarSelectionFill(isActiveWindow: Bool = true) -> Color {
    if isActiveWindow {
      return adaptiveColor(
        light: (0.24, 0.52, 0.33, 0.18),
        dark: (0.40, 0.70, 0.49, 0.24)
      )
    }
    return adaptiveColor(
      light: (0.30, 0.42, 0.33, 0.10),
      dark: (0.38, 0.52, 0.42, 0.14)
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
            displayP3Red: components.0,
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
            displayP3Red: components.0,
            green: components.1,
            blue: components.2,
            alpha: components.3
          )
        }
      )
    #else
      return Color(
        .displayP3,
        red: light.0,
        green: light.1,
        blue: light.2,
        opacity: light.3
      )
    #endif
  }
}
