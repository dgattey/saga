//
//  RichTextDocument.swift
//  Saga
//
//  Created by Dylan Gattey on 7/17/25.
//

import Foundation
import Contentful
#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
let labelColor: PlatformColor = .labelColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
let labelColor: PlatformColor = .label
#endif

extension RichTextDocument {
    /// Converts RichTextDocument to NSAttributedString for rendering.
    var attributedString: NSAttributedString? {
        let transformer = RichTextToAttributedStringTransformer(
            baseFont: PlatformFont.systemFont(ofSize: 14),
            baseColor: labelColor
        )
        return transformer.attributedString(from: self)
    }
}

final class RichTextToAttributedStringTransformer {
    let baseFont: PlatformFont
    let baseColor: PlatformColor
    
    init(baseFont: PlatformFont, baseColor: PlatformColor) {
        self.baseFont = baseFont
        self.baseColor = baseColor
    }
    
    func attributedString(from document: RichTextDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nodes = document.content
        for (index, node) in nodes.enumerated() {
            result.append(attributedString(for: node))
            
            // Add space only if this and the next node are both paragraphs
            if node.nodeType == .paragraph {
                // Don't add if it's the last node, or if the next isn't a paragraph
                if index < nodes.count - 1, nodes[index+1].nodeType == .paragraph {
                    result.append(NSAttributedString(string: "\n\n"))
                }
            }
        }
        return result
    }
    
    private func attributedString(for node: Node) -> NSAttributedString {
        switch node.nodeType {
        case .paragraph:
            return paragraphString(for: node)
        case .h1, .h2, .h3, .h4, .h5, .h6:
            return headingString(for: node, level: node.nodeType)
        case .text:
            guard let textNode = node as? Text else {
                return NSAttributedString()
            }
            return textString(for: textNode)
        case .hyperlink:
            guard let linkNode = node as? Hyperlink else {
                return NSAttributedString()
            }
            return hyperlinkString(for: linkNode)
        default:
            // Handle other nodes or return empty
            return emptyString(for: node)
        }
    }
    
    private func paragraphString(for node: Node) -> NSAttributedString {
        guard let block = node as? BlockNode else {
            return NSAttributedString()
        }
        let mutable = NSMutableAttributedString()
        for child in block.content {
            mutable.append(attributedString(for: child))
        }
        return mutable
    }
    
    private func headingString(for node: Node, level: NodeType) -> NSAttributedString {
        guard let block = node as? BlockNode else {
            return NSAttributedString()
        }
        let fontSize: CGFloat
        switch level {
        case .h1: fontSize = baseFont.pointSize * 1.75
        case .h2: fontSize = baseFont.pointSize * 1.5
        case .h3: fontSize = baseFont.pointSize * 1.3
        case .h4: fontSize = baseFont.pointSize * 1.15
        case .h5: fontSize = baseFont.pointSize * 1.05
        default: fontSize = baseFont.pointSize
        }
        let font = PlatformFont.boldSystemFont(ofSize: fontSize)
        let mutable = NSMutableAttributedString()
        for child in block.content {
            let childAttr = attributedString(for: child).mutableCopy() as! NSMutableAttributedString
            childAttr.addAttribute(.font, value: font, range: NSRange(location: 0, length: childAttr.length))
            mutable.append(childAttr)
        }
        return mutable
    }
    
    private func textString(for text: Text) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor
        ]
        if text.marks.contains(where: { $0.type == .bold }) {
            attrs[.font] = PlatformFont.boldSystemFont(ofSize: baseFont.pointSize)
        }
        if text.marks.contains(where: { $0.type == .italic }) {
            attrs[.obliqueness] = 0.1
        }
        if text.marks.contains(where: { $0.type == .code }) {
            attrs[.font] = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        }
        return NSAttributedString(string: text.value, attributes: attrs)
    }
    
    private func hyperlinkString(for link: Hyperlink) -> NSAttributedString {
        let mutable = NSMutableAttributedString()
        for child in link.content {
            mutable.append(attributedString(for: child))
        }
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.link, value: link.data.uri, range: range)
        return mutable
    }
    
    private func emptyString(for node: Node) -> NSAttributedString {
        print("Warning: unsupported node type \(node.nodeType)")
        return NSAttributedString()
    }
}
