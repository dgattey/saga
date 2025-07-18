//
//  AttributedTextViewer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/17/25.
//

import SwiftUI

struct AttributedTextViewer: View {
    let attributedString: NSAttributedString
    
    @State private var height: CGFloat = 1
    
    var body: some View {
        PlatformAttributedText(
            attributedString: attributedString,
            calculatedHeight: $height
        )
        .frame(height: height)
    }
}

#if os(iOS) || os(tvOS)
import UIKit

struct PlatformAttributedText: UIViewRepresentable {
    let attributedString: NSAttributedString
    @Binding var calculatedHeight: CGFloat
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedString
        // We need to trigger a layout to get the correct width
        DispatchQueue.main.async {
            let fittingSize = CGSize(width: uiView.bounds.width > 0 ? uiView.bounds.width : UIScreen.main.bounds.width - 40, height: .greatestFiniteMagnitude)
            let size = uiView.sizeThatFits(fittingSize)
            if abs(calculatedHeight - size.height) > 1 {
                calculatedHeight = size.height
            }
        }
    }
}
#endif

#if os(macOS)
import AppKit

struct PlatformAttributedText: NSViewRepresentable {
    let attributedString: NSAttributedString
    @Binding var calculatedHeight: CGFloat
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.textStorage?.setAttributedString(attributedString)
        DispatchQueue.main.async {
            guard let layoutManager = nsView.layoutManager, let container = nsView.textContainer else { return }
            // Ensure we are measuring for the current width!
            let width = nsView.bounds.width > 0 ? nsView.bounds.width : 300
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let newHeight = rect.height + 2 * nsView.textContainerInset.height
            if abs(calculatedHeight - newHeight) > 1 {
                calculatedHeight = newHeight
            }
        }
    }
}
#endif
