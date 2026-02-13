//
//  RichTextJSON.swift
//  Saga
//
//  Codable wrapper for Contentful Rich Text JSON. Ensures required CMA
//  properties ("data", "marks") are present on every node before encoding.
//

import Foundation

// MARK: - Rich Text JSON

/// Wrapper for RichTextDocument JSON that can be encoded/decoded
struct RichTextJSON: Codable {
  private let jsonObject: Any

  init(_ jsonObject: Any) {
    // Ensure all Rich Text nodes have required properties for CMA validation
    self.jsonObject = Self.ensureRequiredProperties(in: jsonObject)
  }

  /// Recursively ensures all Rich Text nodes have required properties (CMA validation)
  /// - "data" is required on all nodes
  /// - "marks" is required on text nodes
  private static func ensureRequiredProperties(in object: Any) -> Any {
    guard var dict = object as? [String: Any] else {
      // Handle arrays (like "content" arrays)
      if let array = object as? [Any] {
        return array.map { ensureRequiredProperties(in: $0) }
      }
      return object
    }

    let nodeType = dict["nodeType"] as? String

    // All nodes with nodeType require "data"
    if nodeType != nil && dict["data"] == nil {
      dict["data"] = [String: Any]()
    }

    // Text nodes require "marks" array
    if nodeType == "text" && dict["marks"] == nil {
      dict["marks"] = [[String: Any]]()
    }

    // Recursively process content arrays
    if let content = dict["content"] as? [Any] {
      dict["content"] = content.map { ensureRequiredProperties(in: $0) }
    }

    return dict
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    // Decode as a dictionary, then ensure required properties
    if let dict = try? container.decode([String: AnyCodableValue].self) {
      let rawDict = dict.mapValues { $0.value }
      self.jsonObject = Self.ensureRequiredProperties(in: rawDict)
    } else {
      self.jsonObject = [String: Any]()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    // Use JSONSerialization to get the raw structure, then encode as AnyCodable
    if let data = try? JSONSerialization.data(withJSONObject: jsonObject),
      let decoded = try? JSONDecoder().decode(AnyCodableValue.self, from: data)
    {
      try container.encode(decoded)
    } else {
      try container.encodeNil()
    }
  }
}

// MARK: - AnyCodableValue

/// Helper type for encoding arbitrary JSON values
enum AnyCodableValue: Codable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([AnyCodableValue])
  case dictionary([String: AnyCodableValue])
  case null

  var value: Any {
    switch self {
    case .string(let s): return s
    case .int(let i): return i
    case .double(let d): return d
    case .bool(let b): return b
    case .array(let a): return a.map { $0.value }
    case .dictionary(let d): return d.mapValues { $0.value }
    case .null: return NSNull()
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let int = try? container.decode(Int.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let array = try? container.decode([AnyCodableValue].self) {
      self = .array(array)
    } else if let dict = try? container.decode([String: AnyCodableValue].self) {
      self = .dictionary(dict)
    } else if container.decodeNil() {
      self = .null
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown type")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .bool(let b): try container.encode(b)
    case .array(let a): try container.encode(a)
    case .dictionary(let d): try container.encode(d)
    case .null: try container.encodeNil()
    }
  }
}
