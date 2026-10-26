//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import CoreData

@objc(Asset)
final class Asset: NSManagedObject {
  @NSManaged var id: String
  @NSManaged var urlString: String?

  func apply(_ remote: Contentful.Asset) {
    id = remote.id
    urlString = remote.urlString
  }

  static func linkedContentfulAsset(
    id: String,
    urlString: String,
    in context: NSManagedObjectContext
  ) throws -> Asset {
    let fetchRequest = NSFetchRequest<Asset>(entityName: "Asset")
    fetchRequest.predicate = NSPredicate(format: "id == %@", id)
    fetchRequest.fetchLimit = 1
    let asset = try context.fetch(fetchRequest).first ?? Asset(context: context)
    asset.id = id
    asset.urlString = urlString
    return asset
  }

  var assetURL: URL? {
    urlString.flatMap(URL.init(string:))
  }
}
