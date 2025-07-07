//
//  RichTextDocumentTransformer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Foundation
import Contentful

import Foundation
import Contentful

@objc(RichTextDocumentTransformer)
final class RichTextDocumentTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass { NSData.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let doc = value as? RichTextDocument else { return nil }
        return try? JSONEncoder().encode(doc)
    }
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(RichTextDocument.self, from: data)
    }

    static func register() {
        ValueTransformer.setValueTransformer(RichTextDocumentTransformer(), forName: .richTextDocumentTransformer)
    }
}

extension NSValueTransformerName {
    static let richTextDocumentTransformer = NSValueTransformerName("RichTextDocumentTransformer")
}
