//
//  ContentfulTypes.swift
//  Saga
//
//  Contentful API data types: request/response structures, localization
//  wrappers, and link references used across CMA operations.
//

import Foundation

// MARK: - Resource Types

/// Identifies whether we're working with entries or assets in the CMA
enum ContentfulResourceType: String {
  case entry = "entries"
  case asset = "assets"
}

// MARK: - Response Types

/// The `sys` metadata object returned by every CMA response
struct ContentfulSys: Codable {
  let id: String
  let version: Int
  let createdAt: Date?
  let updatedAt: Date?
  let publishedVersion: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case createdAt
    case updatedAt
    case publishedVersion
  }
}

/// Generic wrapper for any CMA response that contains `sys` metadata
struct ContentfulResource: Codable {
  let sys: ContentfulSys
}

/// Response from upload endpoint
struct ContentfulUploadResponse: Codable {
  let sys: ContentfulUploadSys

  struct ContentfulUploadSys: Codable {
    let id: String
  }
}

// MARK: - Localization Wrapper

/// Generic wrapper for Contentful's locale-based field structure: `{"en-US": value}`
struct Localized<T: Codable>: Codable {
  let enUS: T

  init(_ value: T) {
    self.enUS = value
  }

  enum CodingKeys: String, CodingKey {
    case enUS = "en-US"
  }
}

// MARK: - Link Types

/// A link reference to another Contentful resource
struct ContentfulLink: Codable {
  let sys: LinkSys

  struct LinkSys: Codable {
    let type: String
    let linkType: String
    let id: String

    init(linkType: String, id: String) {
      self.type = "Link"
      self.linkType = linkType
      self.id = id
    }
  }

  init(linkType: String, id: String) {
    self.sys = LinkSys(linkType: linkType, id: id)
  }

  /// Creates a link to an Entry
  static func entry(id: String) -> ContentfulLink {
    ContentfulLink(linkType: "Entry", id: id)
  }

  /// Creates a link to an Asset
  static func asset(id: String) -> ContentfulLink {
    ContentfulLink(linkType: "Asset", id: id)
  }

  /// Creates a link to an Upload (for asset creation)
  static func upload(id: String) -> ContentfulLink {
    ContentfulLink(linkType: "Upload", id: id)
  }
}

// MARK: - Request Envelope

/// Wrapper for encoding request bodies: `{"fields": Fields}`
struct EntryEnvelope<Fields: Encodable>: Encodable {
  let fields: Fields

  init(_ fields: Fields) {
    self.fields = fields
  }
}
