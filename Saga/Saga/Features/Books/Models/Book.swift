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
    
    /// Adds a book to context by newly creating it. Automatically handles duplicates. Threadsafe.
    static func add(to context: NSManagedObjectContext,
                    title: String,
                    author: String,
                    isbn: NSNumber?,
                    readDateStarted: Date?,
                    readDateFinished: Date?,
                    rating: NSNumber?,
                    reviewDescription: RichTextDocument?) async throws {
        // If we had an existing book, just update it in place, including a new Asset if needed
        if let existingBook = try findDuplicate(in: context, title: title, author: author) {
            let newCoverImage: Asset?
            if existingBook.coverImage == nil {
                newCoverImage = try await getOrAddCoverImage(to: context, forISBN: isbn, andTitle: title)
            } else {
                newCoverImage = existingBook.coverImage
            }
            await MainActor.run {
                print("Found duplicate \"\(title)\"")
                existingBook.title = title
                existingBook.isbn ??= isbn
                existingBook.coverImage = newCoverImage
                existingBook.readDateFinished ??= readDateFinished
                existingBook.readDateStarted ??= readDateStarted
                existingBook.rating ??= rating
                existingBook.reviewDescription ??= reviewDescription
            }
            return
        }
        
        // Otherwise, create a new book
        let coverImage = try await getOrAddCoverImage(to: context, forISBN: isbn, andTitle: title)
        await MainActor.run {
            _ = Book(context: context,
                     title: title,
                     author: author,
                     coverImage: coverImage,
                     isbn: isbn,
                     readDateStarted: readDateStarted,
                     readDateFinished: readDateFinished,
                     rating: rating,
                     reviewDescription: reviewDescription)
        }
    }
    
    /// For local creation of book objects
    private convenience init(
        context: NSManagedObjectContext,
        title: String?,
        author: String?,
        coverImage: Asset?,
        isbn: NSNumber?,
        readDateStarted: Date?,
        readDateFinished: Date?,
        rating: NSNumber?,
        reviewDescription: RichTextDocument?
    ) {
        self.init(context: context)
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.updatedAt = self.createdAt
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self.isbn = isbn
        self.readDateStarted = readDateStarted
        self.readDateFinished = readDateFinished
        self.rating = rating
        self.reviewDescription = reviewDescription
    }
    
    /// Finds a duplicate book if it exists so we can update it in place. Duplicate = same author and one of the two titles is contained within
    /// the other. Compares in a case insensitive, localized way.
    private static func findDuplicate(in context: NSManagedObjectContext,
                                      title: String,
                                      author: String) throws -> Book? {
        // Fetch books by author first for efficiency
        let fetchRequest = NSFetchRequest<Book>(entityName: "Book")
        fetchRequest.predicate = NSPredicate(format: "author ==[c] %@", author)
        let existingBooks = try context.fetch(fetchRequest)

        // Filter for the same titles between the two
        return existingBooks.first(where: { existingBook in
            guard let existingTitle = existingBook.title else {
                return false
            }
            return title.localizedCaseInsensitiveContains(existingTitle)
            || existingTitle.localizedCaseInsensitiveContains(title)
        })
    }
    
    /// Gets a cover image URL + adds or fetches the existing Asset for it. Call this only when you're sure that you want to create a
    /// new Asset for this ISBN because it doesn't already exist.
    private static func getOrAddCoverImage(to context: NSManagedObjectContext,
                                           forISBN isbn: NSNumber?,
                                           andTitle title: String) async throws -> Asset? {
        let task = Task(priority: .background) {
            let coverImageUrl: String? = try await {
                guard let isbn = isbn?.stringValue else {
                    return nil
                }
                let url = try await OpenLibraryAPIService.coverImageURL(forISBN: isbn)
                guard let url = url, !url.isEmpty else {
                    return try await BookcoverAPIService.coverImageURL(forISBN: isbn)
                }
                return url
            }()
            return try await Asset.add(to: context, withURL: coverImageUrl)
        }
        return try await task.value
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

