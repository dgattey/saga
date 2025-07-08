//
//  HoverHighlight.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//


import SwiftUI

struct HoverHighlight<Content: View>: View {
    let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        content()
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: -6, bottom: 0, trailing: -6))
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .modifier(HoverModifier(isHovered: $isHovered))
    }
}
