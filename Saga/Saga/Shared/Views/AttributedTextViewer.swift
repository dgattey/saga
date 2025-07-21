//
//  AttributedTextViewer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/17/25.
//

import SwiftUI

struct AttributedTextViewer: View {
    let attributedString: NSAttributedString
    @State private var calculatedHeight: CGFloat = 20 // safe initial guess
    
    var body: some View {
        PlatformAttributedText(
            attributedString: attributedString,
            calculatedHeight: $calculatedHeight
        )
        .frame(height: calculatedHeight) // Only constrain height!
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updateHeight(for: geo.size.width)
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        updateHeight(for: newWidth)
                    }
                    .onChange(of: attributedString) {
                        updateHeight(for: geo.size.width)
                    }
            }
        )
    }
    
    private func updateHeight(for width: CGFloat) {
        guard width > 0 else { return }
        let newHeight = measuredHeight(for: attributedString, width: width)
        if abs(newHeight - calculatedHeight) > 1 {
            calculatedHeight = newHeight
        }
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
        // Allows flexible height, but it's controlled by SwiftUI's frame.
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedString
        // Set width, height doesn't matter (handled by SwiftUI frame)
        let width = uiView.bounds.width > 0 ? uiView.bounds.width : UIScreen.main.bounds.width
        uiView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    }
}

#elseif os(macOS)
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
        let width = nsView.bounds.width > 0 ? nsView.bounds.width : 300
        nsView.textContainer?.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    }
}
#endif

// MARK: - Sizing function

func measuredHeight(for attributedString: NSAttributedString, width: CGFloat) -> CGFloat {
    let textStorage = NSTextStorage(attributedString: attributedString)
    let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 0
    textContainer.lineBreakMode = .byWordWrapping
    textContainer.maximumNumberOfLines = 0
    
    let layoutManager = NSLayoutManager()
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    return ceil(usedRect.height)
}
