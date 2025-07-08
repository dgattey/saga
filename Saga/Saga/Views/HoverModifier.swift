//
//  HoverModifier.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//


import SwiftUI

struct HoverModifier: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .pointerStyle(isHovered ? .link : .default)
            .onHover { hovering in
                isHovered = hovering
            }
        #elseif os(iOS)
        if #available(iOS 13.4, *) {
            content
                .onHover { hovering in
                    isHovered = hovering
                }
                .hoverEffect(.highlight)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
