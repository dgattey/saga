//
//  GeneralSettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/16/26.
//

import SwiftUI

/// Software updates (macOS only) and interactive spring animation tuning.
struct GeneralSettingsView: View {
  @EnvironmentObject var animationSettings: AnimationSettings
  #if os(macOS)
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
  #endif

  var body: some View {
    Form {
      #if os(macOS)
        Section("Updates") {
          Toggle(
            "Automatically check for updates",
            isOn: $updaterViewModel.automaticallyChecksForUpdates
          )
          .toggleStyle(.switch)
          .disabled(!updaterViewModel.isConfigured)
          .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)

          Toggle(
            "Automatically download updates",
            isOn: $updaterViewModel.automaticallyDownloadsUpdates
          )
          .toggleStyle(.switch)
          .disabled(
            !updaterViewModel.isConfigured || !updaterViewModel.automaticallyChecksForUpdates
          )
          .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)

          LabeledContent("Software updates") {
            Button("Check for Updates…") {
              updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
            .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
          }
        }
      #endif

      Section("Animations") {
        springSlider("Spring response", value: $animationSettings.springResponse)
        springSlider("Spring damping", value: $animationSettings.springDamping)
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
