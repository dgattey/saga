//
//  CacheSectionView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

struct CacheSectionView: View {
  let limitLabel: String
  @Binding var limitGB: Double
  @Binding var limitIndex: Double
  let currentSizeBytes: Int64
  let options: [Double]
  let onLimitChange: () -> Void

  var body: some View {
    SettingsSliderView(
      label: limitLabel,
      formattedValue: Self.formatLimit(limitGB),
      value: $limitIndex,
      range: 0...Double(options.count - 1),
      step: 1,
      subtitle: "Current usage",
      subtitleValue: Self.formatBytes(currentSizeBytes)
    )
    .onChange(of: limitGB) { _, _ in
      onLimitChange()
    }
    .onChange(of: limitIndex) { _, newValue in
      let index = max(0, min(options.count - 1, Int(newValue.rounded())))
      let newLimit = options[index]
      if limitGB != newLimit {
        limitGB = newLimit
      }
    }
  }

  private static func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  private static func formatLimit(_ value: Double) -> String {
    if value == 0 {
      return "Unlimited"
    }
    let megabytes = Int(value * 1000)
    if megabytes < 1000 {
      return "\(megabytes) MB"
    }
    return "\(Int(value)) GB"
  }
}
