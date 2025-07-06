//
//  Book.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//


import Foundation
import CoreData
import Contentful
import ContentfulPersistence

@objc(Book)
class Book: NSManagedObject, EntryPersistable, Identifiable {
    static let contentTypeId = "book"

    @NSManaged var id: String
    @NSManaged var localeCode: String?
    @NSManaged var updatedAt: Date?
    @NSManaged var createdAt: Date?

    @NSManaged var title: String?
//    @NSManaged var isbn: NSNumber?           // 13-digit ISBN13
//    @NSManaged var author: String?
//    @NSManaged var coverImageId: String?     // Asset ID for cover image
//    @NSManaged var readDateStarted: Date?
//    @NSManaged var readDateFinished: Date?
//    @NSManaged var rating: NSNumber?
//    @NSManaged var reviewDescription: String? // Rich text (serialized as needed)
    
    /*
     For local testing, we need a title alone initializer
     */
    convenience init(context: NSManagedObjectContext, title: String) {
        self.init(context: context)
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.updatedAt = self.createdAt
        self.title = title
    }

    static func fieldMapping() -> [Contentful.FieldName: String] {
        return [
            "title": "title",
            "isbn": "isbn",
            "author": "author",
            "coverImage": "coverImageId",
            "readDateStarted": "readDateStarted",
            "readDateFinished": "readDateFinished",
            "rating": "rating",
            "reviewDescription": "reviewDescription"
        ]
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Book> {
        return NSFetchRequest<Book>(entityName: "Book")
    }
}
