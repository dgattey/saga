//
//  VisualEffectView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/23/26.
//

import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()

        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground

        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Window Background Modifier

struct WindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VisualEffectView().ignoresSafeArea())
    }
}

extension View {
    /// Applies the standard window background effect to any view.
    /// Use this on the root view of every Scene for consistent styling.
    func windowBackground() -> some View {
        modifier(WindowBackgroundModifier())
    }
}
