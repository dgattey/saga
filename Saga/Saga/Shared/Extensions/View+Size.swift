//
//  View+Size.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

private struct ViewSizePreferenceKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    value = nextValue()
  }
}

extension View {
  func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
    background(
      GeometryReader { geometry in
        Color.clear
          .preference(key: ViewSizePreferenceKey.self, value: geometry.size)
      }
    )
    .onPreferenceChange(ViewSizePreferenceKey.self, perform: onChange)
  }
}
