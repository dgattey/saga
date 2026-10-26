//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import ContentfulPersistence
import CoreData

@objc(Asset)
final class Asset: NSManagedObject, AssetPersistable {
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
    let asset = Asset(context: context)
    asset.id = id
    asset.createdAt = Date()
    asset.updatedAt = asset.createdAt
    asset.urlString = urlString
    return asset
  }

  var assetURL: URL? {
    guard let urlString = urlString else { return nil }
    return URL(string: urlString)
  }

  var isContentfulManaged: Bool {
    localeCode != nil
  }
}
