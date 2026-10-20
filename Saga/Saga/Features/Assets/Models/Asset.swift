//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import ContentfulPersistence
import CoreData
import Ifrit

@objc(Asset)
final class Asset: NSManagedObject, AssetPersistable, SearchableModel {
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

  /// Returns the asset with Contentful ID `id`, creating a placeholder pointing at `urlString`
  /// when it hasn't synced yet. The next Contentful sync fills in the rest by ID.
  /// Must be called on `context`'s queue.
  static func linkedContentfulAsset(
    id: String,
    urlString: String,
    in context: NSManagedObjectContext
  ) throws -> Asset {
    let fetchRequest = NSFetchRequest<Asset>(entityName: "Asset")
    fetchRequest.predicate = NSPredicate(format: "id == %@", id)
    fetchRequest.fetchLimit = 1
    if let existing = try context.fetch(fetchRequest).first {
      return existing
    }
    let asset = Asset(context: context, urlString: urlString)
    asset.id = id
    return asset
  }

  /// Finds a duplicate asset by url if it exists so we can update it in place.
  private static func findDuplicate(
    in context: NSManagedObjectContext,
    urlString: String
  ) throws -> Asset? {
    // Fetch books by author first for efficiency
    let fetchRequest = NSFetchRequest<Asset>(entityName: "Asset")
    fetchRequest.predicate = NSPredicate(format: "urlString ==[c] %@", urlString)
    fetchRequest.fetchLimit = 1
    let existingAssets = try context.fetch(fetchRequest)
    return existingAssets.first
  }

  var assetURL: URL? {
    guard let urlString = urlString else { return nil }
    return URL(string: urlString)
  }

  /// Whether this asset was synced from Contentful (and so has a real Contentful asset ID).
  /// ContentfulPersistence always sets `localeCode`; assets created locally via `add` never do.
  var isContentfulManaged: Bool {
    localeCode != nil
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

final class AssetDTO: SearchableDTO, @unchecked Sendable {
  let id: String
  let title: String?
  let fileName: String?
  let urlString: String?
  let fuzzySearchableProperties: [FuseProp]

  init(id: String, title: String?, fileName: String?, urlString: String?) {
    self.id = id
    self.title = title
    self.fileName = fileName
    self.urlString = urlString
    self.fuzzySearchableProperties = [
      FuseProp(title ?? ""),
      FuseProp(fileName ?? ""),
    ]
  }

  static var fuzzySearchKeyPaths: [PartialKeyPath<AssetDTO>] = [
    \AssetDTO.title,
    \AssetDTO.fileName,
  ]
}
