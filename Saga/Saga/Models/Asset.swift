//
//  Asset.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import ContentfulPersistence

@objc(Asset)
final class Asset: NSManagedObject, AssetPersistable, SearchableModel {
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
    
    var assetURL: URL? {
        guard let urlString = urlString else { return nil }
        return URL(string: urlString)
    }
    
    func toDTO() -> AssetDTO {
        AssetDTO(
            id: self.id,
            title: self.title,
            fileName: self.fileName
        )
    }
}

final class AssetDTO: SearchableDTO {
    let id: String
    let title: String?
    let fileName: String?
    
    init(id: String, title: String?, fileName: String?) {
        self.id = id
        self.title = title
        self.fileName = fileName
    }

    static var searchableKeyPaths: [PartialKeyPath<AssetDTO>] = [
        \AssetDTO.title,
        \AssetDTO.fileName
    ]

    func stringValue(for keyPath: PartialKeyPath<AssetDTO>) -> String {
        switch keyPath {
        case \AssetDTO.title: return title ?? ""
        case \AssetDTO.fileName: return fileName ?? ""
        default: return ""
        }
    }
}
