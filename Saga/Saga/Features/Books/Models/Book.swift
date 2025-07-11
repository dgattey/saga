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
final class Book: NSManagedObject, EntryPersistable, SearchableModel {
    static let contentTypeId = "book"

    @NSManaged var id: String
    @NSManaged var localeCode: String?
    @NSManaged var updatedAt: Date?
    @NSManaged var createdAt: Date?

    @NSManaged var title: String?
    @NSManaged var isbn: NSNumber?           // 13-digit ISBN13
    @NSManaged var author: String?
    @NSManaged var coverImage: Asset?     // Asset ID for cover image
    @NSManaged var readDateStarted: Date?
    @NSManaged var readDateFinished: Date?
    @NSManaged var rating: NSNumber?
    @NSManaged var reviewDescription: RichTextDocument?
    
    /// For local creation of book objects
    convenience init(
        context: NSManagedObjectContext,
        title: String?,
        author: String?,
        coverImage: Asset?,
        isbn: String?,
        readDateStarted: Date?,
        readDateFinished: Date?,
        rating: Int?,
        reviewDescription: RichTextDocument?
    ) {
        self.init(context: context)
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.updatedAt = self.createdAt
        self.title = title
        self.author = author
        self.coverImage = coverImage
        if let isbnStr = isbn, let isbnNum = Int64(isbnStr) {
            self.isbn = NSNumber(value: isbnNum)
        }
        self.readDateStarted = readDateStarted
        self.readDateFinished = readDateFinished
        if let rating = rating {
            self.rating = NSNumber(value: rating)
        }
        self.reviewDescription = reviewDescription
    }

    static func fieldMapping() -> [Contentful.FieldName: String] {
        return [
            "title": "title",
            "isbn": "isbn",
            "author": "author",
            "coverImage": "coverImage",
            "readDateStarted": "readDateStarted",
            "readDateFinished": "readDateFinished",
            "rating": "rating",
            "reviewDescription": "reviewDescription"
        ]
    }
    
    func toDTO() -> BookDTO {
        BookDTO(
            id: self.id,
            title: self.title,
            isbn: self.isbn?.stringValue,
            author: self.author,
            coverImage: self.coverImage?.toDTO(),
            readDateStarted: self.readDateStarted?.description(with: .current),
            readDateFinished: self.readDateFinished?.description(with: .current),
            rating: self.rating?.stringValue,
            reviewDescription: self.reviewDescription?.description
        )
    }
}

final class BookDTO: SearchableDTO {
    let id: String
    let title: String?
    let isbn: String?
    let author: String?
    let coverImage: AssetDTO?
    let readDateStarted: String?
    let readDateFinished: String?
    let rating: String?
    let reviewDescription: String?

    init(
        id: String,
        title: String?,
        isbn: String?,
        author: String?,
        coverImage: AssetDTO?,
        readDateStarted: String?,
        readDateFinished: String?,
        rating: String?,
        reviewDescription: String?
    ) {
        self.id = id
        self.title = title
        self.isbn = isbn
        self.author = author
        self.coverImage = coverImage
        self.readDateStarted = readDateStarted
        self.readDateFinished = readDateFinished
        self.rating = rating
        self.reviewDescription = reviewDescription
    }

    static var searchableKeyPaths: [PartialKeyPath<BookDTO>] = [
        \BookDTO.title,
        \BookDTO.isbn,
        \BookDTO.author,
        \BookDTO.coverImage,
        \BookDTO.readDateStarted,
        \BookDTO.readDateFinished,
        \BookDTO.rating,
        \BookDTO.reviewDescription
    ]

    func stringValue(for keyPath: PartialKeyPath<BookDTO>) -> String {
        switch keyPath {
        case \BookDTO.title: return title ?? ""
        case \BookDTO.isbn: return isbn ?? ""
        case \BookDTO.author: return author ?? ""
        case \BookDTO.coverImage: return coverImage?.searchableStrings().joined(separator: " ") ?? ""
        case \BookDTO.readDateStarted: return readDateStarted ?? ""
        case \BookDTO.readDateFinished: return readDateFinished ?? ""
        case \BookDTO.rating: return rating ?? ""
        case \BookDTO.reviewDescription: return reviewDescription ?? ""
        default: return ""
        }
    }
}

