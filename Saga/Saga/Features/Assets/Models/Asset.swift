//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import ContentfulPersistence
import CoreData

@objc(Asset)
final class Asset: NSManagedObject, AssetPersistable, SearchableModel, ContentfulSyncable,
  ContentfulVersionTracking
{
  static let contentTypeId = "asset"

  @NSManaged var id: String
  @NSManaged var localeCode: String?
  @NSManaged var updatedAt: Date?
  @NSManaged var createdAt: Date?

  @NSManaged var title: String?
  @NSManaged var assetDescription: String?
  @NSManaged var urlString: String?
  @NSManaged var fileName: String?
  @NSManaged var fileType: String?
  @NSManaged var size: NSNumber?
  @NSManaged var width: NSNumber?
  @NSManaged var height: NSNumber?

  /// Tracks whether this asset has local changes not yet synced to Contentful
  @NSManaged var isDirty: Bool

  /// The Contentful version number for optimistic locking during two-way sync
  @NSManaged var contentfulVersion: Int

  /// Properties that should NOT trigger isDirty (sync metadata)
  private static let syncMetadataKeys: Set<String> = [
    "isDirty", "contentfulVersion", "updatedAt", "createdAt", "localeCode",
  ]

  // MARK: - Automatic Dirty Tracking

  override func willSave() {
    super.willSave()

    // Skip if being deleted
    guard !isDeleted else { return }

    // Only mark dirty for user edits on the main queue context.
    // ContentfulPersistence writes to background contexts, and markClean operations
    // also use background contexts -- those should not trigger dirty marking.
    guard managedObjectContext?.concurrencyType == .mainQueueConcurrencyType else { return }

    // Check if any non-metadata properties changed
    let changedKeys = Set(changedValues().keys)
    let contentKeys = changedKeys.subtracting(Self.syncMetadataKeys)

    if !contentKeys.isEmpty {
      // Use primitiveValue to avoid triggering another willSave
      // Always update updatedAt for accurate conflict resolution (latest-wins)
      setPrimitiveValue(Date(), forKey: "updatedAt")
      // Only set isDirty if not already dirty (avoid redundant write)
      if !isDirty {
        setPrimitiveValue(true, forKey: "isDirty")
      }
    }
  }

  /// Adds a book to context by newly creating it. Automatically handles duplicates. Threadsafe.
  static func add(
    to context: NSManagedObjectContext,
    withURL urlString: String?
  ) async throws -> Asset? {
    guard let urlString = urlString else {
      return nil
    }
    return try await context.perform {
      if let existing = try findDuplicate(in: context, urlString: urlString) {
        return existing
      }
      return Asset(context: context, urlString: urlString)
    }
  }

  /// For local object construction
  private convenience init(
    context: NSManagedObjectContext,
    urlString: String
  ) {
    self.init(context: context)
    self.id = UUID().uuidString
    self.createdAt = Date()
    self.updatedAt = self.createdAt
    self.urlString = urlString
  }

  /// Finds a duplicate asset by url if it exists so we can update it in place.
  private static func findDuplicate(
    in context: NSManagedObjectContext,
    urlString: String
  ) throws -> Asset? {
    // Fetch books by author first for efficiency
    let fetchRequest = NSFetchRequest<Asset>(entityName: "Asset")
    fetchRequest.predicate = NSPredicate(format: "urlString ==[c] %@", urlString)
    let existingAssets = try context.fetch(fetchRequest)
    return existingAssets.first
  }

  var assetURL: URL? {
    guard let urlString = urlString else { return nil }
    return URL(string: urlString)
  }

  func toDTO() -> AssetDTO {
    AssetDTO(
      id: self.id,
      title: self.title,
      fileName: self.fileName,
      urlString: self.urlString
    )
  }
}

final class AssetDTO: SearchableDTO {
  let id: String
  let title: String?
  let fileName: String?
  let urlString: String?

  init(id: String, title: String?, fileName: String?, urlString: String?) {
    self.id = id
    self.title = title
    self.fileName = fileName
    self.urlString = urlString
  }

  static var fuzzySearchKeyPaths: [PartialKeyPath<AssetDTO>] = [
    \AssetDTO.title,
    \AssetDTO.fileName,
  ]
}
