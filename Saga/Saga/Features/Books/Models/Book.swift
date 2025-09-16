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

/// A simple enum to wrap dates in an enum for status
enum ReadingStatus: String, CaseIterable {
    case notStarted
    case reading
    case read
    
    mutating func advance() {
        switch self {
        case .notStarted:
            self = .reading
        case .reading:
            self = .read
        case .read:
            break
        }
    }
    
    init(readDateStarted: Date?, readDateFinished: Date?) {
        if readDateFinished != nil {
            self = .read
        } else if readDateStarted != nil {
            self = .reading
        } else {
            self = .notStarted
        }
    }
}

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
    
    var readingStatus: ReadingStatus {
        .init(readDateStarted: readDateStarted, readDateFinished: readDateFinished)
    }
    
    /// Adds a book to context by newly creating it. Automatically handles duplicates. Threadsafe.
    static func add(to context: NSManagedObjectContext,
                    title: String,
                    author: String,
                    getISBN: () async throws -> NSNumber?,
                    readDateStarted: Date?,
                    readDateFinished: Date?,
                    rating: NSNumber?,
                    reviewDescription: RichTextDocument?) async throws {
        
        // Check for duplicates first
        let existingBook = try findDuplicate(in: context, title: title, author: author)
        
        if let existingBook = existingBook {
            // Handle existing book update
            let currentISBN = existingBook.isbn
            let needsCoverImage = existingBook.coverImage == nil
            
            // Get ISBN if we don't have one - evaluate the closure first
            let isbn: NSNumber?
            if currentISBN != nil {
                isbn = currentISBN
            } else {
                isbn = try await getISBN()
            }
            
            // Get cover image if we don't have one
            if needsCoverImage, let isbn = isbn {
                let coverImageURL = await getCoverImageURL(forISBN: isbn, andTitle: title)
                if let url = coverImageURL {
                    let asset = try await Asset.add(to: context, withURL: url)
                    existingBook.coverImage = asset
                }
            }
            
            // Update the existing book directly (no closure needed)
            print("Found duplicate \"\(title)\"")
            existingBook.title = title
            existingBook.isbn ??= isbn
            existingBook.readDateFinished ??= readDateFinished
            existingBook.readDateStarted ??= readDateStarted
            existingBook.rating ??= rating
            existingBook.reviewDescription ??= reviewDescription
            
        } else {
            // Create new book
            let isbn = try await getISBN()
            let coverImageURL = await getCoverImageURL(forISBN: isbn, andTitle: title)
            let coverAsset = try await Asset.add(to: context, withURL: coverImageURL)
            
            // Create the book directly (no closure needed)
            _ = Book(context: context,
                     title: title,
                     author: author,
                     coverImage: coverAsset,
                     isbn: isbn,
                     readDateStarted: readDateStarted,
                     readDateFinished: readDateFinished,
                     rating: rating,
                     reviewDescription: reviewDescription)
        }
    }
    
    /// Helper method to get cover image URL without creating Asset
    private static func getCoverImageURL(forISBN isbn: NSNumber?, andTitle title: String) async -> String? {
        guard let isbn = isbn?.stringValue else {
            return nil
        }
        
        do {
            if let url = try await OpenLibraryAPIService.coverImageURL(forISBN: isbn), !url.isEmpty {
                return url
            }
            return try await BookcoverAPIService.coverImageURL(forISBN: isbn)
        } catch {
            return nil
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
        let fetchTask: Task<String?, Error> = Task.detached(priority: .background) {
            guard let isbn = isbn?.stringValue else {
                return nil
            }
            let url = try await OpenLibraryAPIService.coverImageURL(forISBN: isbn)
            guard let url = url, !url.isEmpty else {
                return try await BookcoverAPIService.coverImageURL(forISBN: isbn)
            }
            return url
        }
        let coverImageUrl = try await fetchTask.value
        return try await Asset.add(to: context, withURL: coverImageUrl)
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
            reviewDescription: self.reviewDescription?.attributedString?.string
        )
    }
}

final class BookDTO: SearchableDTO, CustomStringConvertible {
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
    
    var description: String {
        return self.title ?? "Untitled BookDTO"
    }
    
    static var nestedSearchableDTOKeyPaths: [PartialKeyPath<BookDTO>] = [
        \BookDTO.coverImage,
    ]

    static var fuzzySearchKeyPaths: [PartialKeyPath<BookDTO>] = [
        \BookDTO.title,
        \BookDTO.isbn,
        \BookDTO.author,
        \BookDTO.readDateStarted,
        \BookDTO.readDateFinished,
        \BookDTO.rating,
        \BookDTO.reviewDescription
    ]
}

