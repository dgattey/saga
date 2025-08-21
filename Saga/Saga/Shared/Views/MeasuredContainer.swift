//
//  MeasuredContainerWidth.swift
//  Saga
//
//  Created by Dylan Gattey on 8/21/25.
//

import SwiftUI

/// Adds an background that doesn't impact sizing to measure the size of the parent.
/// Useful for responsive layouts.
struct MeasuredContainer<Content: View>: View {
    @State private var containerSize: CGSize = .zero
    
    let content: (_ containerSize: CGSize) -> Content
    
    init(@ViewBuilder content: @escaping (_ containerSize: CGSize) -> Content) {
        self.content = content
    }
    
    var body: some View {
        self.content(containerSize)
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometry.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { newSize in
                containerSize = newSize
            }
    }
}

/// Preference key for passing size data
private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
