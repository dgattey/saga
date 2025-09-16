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
    static func add(to context: NSManagedObjectContext,
                    withURL urlString: String?) async throws -> Asset? {
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
    private static func findDuplicate(in context: NSManagedObjectContext,
                                      urlString: String) throws -> Asset? {
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
        \AssetDTO.fileName
    ]
}
