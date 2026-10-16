//
//  CacheLimitRow.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

/// A grouped-form row with a stepped slider for a disk cache limit, current usage as the
/// subtitle, and the selected limit as the trailing value.
struct CacheLimitRow: View {
  static let limitOptions: [Double] = [0.1, 0.5, 1, 5, 10, 0]

  let title: String
  @Binding var limitGB: Double
  let currentSizeBytes: Int64
  let onLimitChange: () -> Void

  @State private var limitIndex: Double = 3

  var body: some View {
    LabeledContent {
      HStack(spacing: 10) {
        Slider(value: $limitIndex, in: 0...Double(Self.limitOptions.count - 1), step: 1) {
          Text(title)
        }
        .labelsHidden()
        .frame(maxWidth: 180)
        Text(Self.formatLimit(limitGB))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(minWidth: 64, alignment: .trailing)
      }
    } label: {
      Text(title)
      Text("\(Self.formatBytes(currentSizeBytes)) used")
    }
    .onAppear {
      limitIndex = Double(Self.limitOptions.firstIndex(of: limitGB) ?? 3)
    }
    .onChange(of: limitIndex) { _, newValue in
      let index = max(0, min(Self.limitOptions.count - 1, Int(newValue.rounded())))
      let newLimit = Self.limitOptions[index]
      if limitGB != newLimit {
        limitGB = newLimit
      }
    }
    .onChange(of: limitGB) { _, _ in
      onLimitChange()
    }
  }

  static func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  static func formatLimit(_ value: Double) -> String {
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
