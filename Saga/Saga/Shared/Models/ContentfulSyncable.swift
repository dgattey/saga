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

// MARK: - Dirty Tracking Helper

/// Properties that should NOT trigger isDirty (sync metadata).
/// Shared by Book and Asset willSave() implementations.
let contentfulSyncMetadataKeys: Set<String> = [
  "isDirty", "contentfulVersion", "updatedAt", "createdAt", "localeCode",
]

/// Helper for willSave() dirty-tracking logic.
/// Call from NSManagedObject.willSave() after super.willSave() and guard !isDeleted.
/// Marks the object dirty and updates updatedAt when non-metadata properties change.
func applyDirtyTrackingIfNeeded(
  on object: NSManagedObject,
  isDirty: Bool,
  changedKeys: Set<String>
) {
  // Only mark dirty for user edits on the main queue context.
  // ContentfulPersistence writes to background contexts, and markClean operations
  // also use background contexts -- those should not trigger dirty marking.
  guard object.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType else { return }

  // Check if any non-metadata properties changed
  let contentKeys = changedKeys.subtracting(contentfulSyncMetadataKeys)

  if !contentKeys.isEmpty {
    // Use primitiveValue to avoid triggering another willSave
    // Always update updatedAt for accurate conflict resolution (latest-wins)
    object.setPrimitiveValue(Date(), forKey: "updatedAt")
    // Only set isDirty if not already dirty (avoid redundant write)
    if !isDirty {
      object.setPrimitiveValue(true, forKey: "isDirty")
    }
  }
}

// MARK: - Pending Deletion Tracking

/// Records a pending deletion for upstream sync when a syncable object is deleted.
/// Call from NSManagedObject.willSave() when isDeleted is true.
/// Only records deletions from the main queue context (user-initiated).
func recordPendingDeletionIfNeeded(
  on object: NSManagedObject,
  resourceType: ContentfulResourceType,
  id: String
) {
  guard object.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType else { return }
  PendingDeletionStore.shared.add(resourceType: resourceType, id: id)
}

/// Thread-safe store for tracking local deletions that need to be synced upstream.
/// Populated from willSave() (synchronous) and drained during push in TwoWaySyncService.
final class PendingDeletionStore {
  static let shared = PendingDeletionStore()

  struct Deletion {
    let resourceType: ContentfulResourceType
    let id: String
  }

  private var deletions: [Deletion] = []
  private let lock = NSLock()

  private init() {}

  /// Records a deletion to be pushed upstream on next sync.
  func add(resourceType: ContentfulResourceType, id: String) {
    lock.lock()
    defer { lock.unlock() }
    if !deletions.contains(where: { $0.resourceType == resourceType && $0.id == id }) {
      deletions.append(Deletion(resourceType: resourceType, id: id))
    }
  }

  /// Returns and removes all pending deletions.
  func drainAll() -> [Deletion] {
    lock.lock()
    defer { lock.unlock() }
    let result = deletions
    deletions.removeAll()
    return result
  }

  /// Re-adds deletions that failed to sync (for retry on next sync).
  func restore(_ items: [Deletion]) {
    lock.lock()
    defer { lock.unlock() }
    deletions.append(contentsOf: items)
  }

  /// The number of pending deletions.
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return deletions.count
  }

  /// Removes all pending deletions without processing them (used during reset).
  func clear() {
    lock.lock()
    defer { lock.unlock() }
    deletions.removeAll()
  }
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
