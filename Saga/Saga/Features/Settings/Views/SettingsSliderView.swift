//
//  SettingsSliderView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/26/26.
//

import SwiftUI

/// A reusable slider component for settings with consistent styling.
/// Shows a label, value pill, full-width slider, and optional subtitle.
struct SettingsSliderView: View {
  let label: String
  let formattedValue: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let subtitle: String?
  let subtitleValue: String?

  init(
    label: String,
    formattedValue: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    subtitle: String? = nil,
    subtitleValue: String? = nil
  ) {
    self.label = label
    self.formattedValue = formattedValue
    self._value = value
    self.range = range
    self.step = step
    self.subtitle = subtitle
    self.subtitleValue = subtitleValue
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(label)
        Spacer()
        Text(formattedValue)
          .font(.callout.monospaced())
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Capsule()
              .fill(.quaternary)
          )
      }
      ZStack {
        Capsule()
          .fill(.quaternary)
          .frame(height: 6)
        Slider(value: $value, in: range, step: step)
          .labelsHidden()
          .tint(.accentColor)
      }
      if let subtitle, let subtitleValue {
        HStack {
          Text(subtitle)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
          Spacer()
          Text(subtitleValue)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
