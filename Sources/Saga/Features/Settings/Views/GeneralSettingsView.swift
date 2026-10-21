//
//  GeneralSettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/16/26.
//

import DylUI
import SwiftUI

/// Software updates (macOS only) and interactive spring animation tuning.
struct GeneralSettingsView: View {
  @Environment(AnimationSettings.self) var animationSettings

  var body: some View {
    Group {
      #if os(macOS)
        UpdatesSection()
      #endif

      Section("Animations") {
        springSlider("Spring response", value: Bindable(animationSettings).springResponse)
        springSlider("Spring damping", value: Bindable(animationSettings).springDamping)
        LabeledContent("Defaults") {
          Button("Reset") {
            animationSettings.resetToDefaults()
          }
          .disabled(isAtDefaults)
        }
      }
    }
  }

  private var isAtDefaults: Bool {
    animationSettings.springResponse == AnimationSettings.defaultSpringResponse
      && animationSettings.springDamping == AnimationSettings.defaultSpringDamping
  }

  private func springSlider(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        Slider(value: value, in: 0.1...1.0, step: 0.05) {
          Text(title)
        }
        .labelsHidden()
        .frame(maxWidth: 200)
        Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
      }
    }
  }
}
