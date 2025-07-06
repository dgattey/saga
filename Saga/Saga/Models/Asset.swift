//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import ContentfulPersistence

@objc(Asset)
class Asset: NSManagedObject, AssetPersistable, Identifiable {
    static let contentTypeId = "asset"
    
    @NSManaged var title: String?
    @NSManaged var assetDescription: String?
    @NSManaged var urlString: String?
    @NSManaged var fileName: String?
    @NSManaged var fileType: String?
    @NSManaged var size: NSNumber?
    @NSManaged var width: NSNumber?
    @NSManaged var height: NSNumber?
    @NSManaged var id: String
    @NSManaged var localeCode: String?
    @NSManaged var updatedAt: Date?
    @NSManaged var createdAt: Date?
}
