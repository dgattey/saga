//
//  ContentfulSyncable.swift
//  Saga
//
//  Protocols defining the contract for Core Data models that participate
//  in two-way sync with Contentful. Conforming types live in their
//  respective +Contentful files (e.g. Book+Contentful.swift).
//

import CoreData
import Foundation

// MARK: - ContentfulVersionTracking

/// Protocol for tracking Contentful version numbers on local objects
protocol ContentfulVersionTracking {
  var contentfulVersion: Int { get set }
}

// MARK: - ContentfulSyncable

/// Protocol for objects that can be synced to Contentful
protocol ContentfulSyncable {
  /// The Contentful entry/asset ID
  var id: String { get }
  /// When the object was last updated locally
  var updatedAt: Date? { get }
  /// Whether this object has local changes not yet synced
  var isDirty: Bool { get set }
}

// MARK: - ContentfulPushable

/// Protocol for entities that can be pushed to Contentful via CMA
/// Conforming types define how their fields are serialized and whether they're entries or assets
protocol ContentfulPushable: NSManagedObject, ContentfulSyncable, ContentfulVersionTracking {
  associatedtype FieldsPayload: Encodable

  /// The CMA resource type (entry or asset)
  static var resourceType: ContentfulResourceType { get }

  /// The Contentful content type ID for CMA requests (required for entries, nil for assets)
  /// Named differently from EntryPersistable.contentTypeId to avoid conflicts
  static var cmaContentTypeId: String? { get }

  /// The CoreData entity name
  static var entityName: String { get }

  /// Builds the Codable fields payload for this entity
  func buildFieldsPayload() -> FieldsPayload

  /// Display title for logging (e.g., book title or asset filename)
  var displayTitle: String? { get }
}

extension ContentfulPushable {
  /// Encodes the fields payload wrapped in an EntryEnvelope to JSON Data.
  /// This works with existential types because it's called on the concrete `Self`.
  func encodeFieldsEnvelope() throws -> Data {
    let envelope = EntryEnvelope(buildFieldsPayload())
    return try JSONEncoder().encode(envelope)
  }
}
