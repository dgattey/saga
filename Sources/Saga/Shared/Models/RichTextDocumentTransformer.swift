//
//  RichTextDocumentTransformer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import Foundation

@objc(RichTextDocumentTransformer)
final class RichTextDocumentTransformer: ValueTransformer {
  override class func transformedValueClass() -> AnyClass { NSData.self }
  override class func allowsReverseTransformation() -> Bool { true }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let doc = value as? RichTextDocument else { return nil }
    do {
      return try JSONEncoder().encode(doc)
    } catch {
      LoggerService.log(
        "Failed to encode RichTextDocument",
        error: error,
        surface: .richText
      )
      return nil
    }
  }
  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let data = value as? Data else { return nil }
    do {
      return try JSONDecoder().decode(RichTextDocument.self, from: data)
    } catch {
      LoggerService.log(
        "Failed to decode RichTextDocument",
        error: error,
        surface: .richText
      )
      return nil
    }
  }

  static func register() {
    ValueTransformer.setValueTransformer(
      RichTextDocumentTransformer(), forName: .richTextDocumentTransformer)
  }
}

extension NSValueTransformerName {
  static let richTextDocumentTransformer = NSValueTransformerName("RichTextDocumentTransformer")
}

extension RichTextDocument {
  convenience init(fromPlainText text: String) {
    let normalized =
      text
      .replacingOccurrences(of: "<br>", with: "\n")
      .replacingOccurrences(of: "<br/>", with: "\n")
      .replacingOccurrences(of: "\r\n", with: "\n")

    // Get all non-empty paragraphs out
    let rawParagraphs = normalized.components(separatedBy: .newlines)
    let paragraphs =
      rawParagraphs
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    let nodes: [Paragraph] = paragraphs.map { line in
      let textNode = Text(value: line, marks: [])
      return Paragraph(nodeType: .paragraph, content: [textNode])
    }

    self.init(content: nodes)
  }
}
