//
//  BookCSVParser.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import Foundation
import CoreData
import Contentful
import SwiftCSV

private enum BookCSVField: String {
    case title = "Title"
    case author = "Author"
    case isbn = "ISBN13"
    case rating = "My Rating"
    case review = "My Review"
    case dateAdded = "Date Added"
    case dateRead = "Date Read"
    case exclusiveShelf = "Exclusive Shelf"
}

private extension Dictionary where Key == String, Value == String {
    func value(for field: BookCSVField) -> String? {
        self[field.rawValue]
    }
}

struct BookCSVParser {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
    
    private init() {}
    
    /// Runs CSV parse from a file URL with a context, then delegates to main to save it
    static func parseCSV(into context: NSManagedObjectContext, from csvFileURL: URL) async throws -> Void {
        let csv = try NamedCSV(url: csvFileURL)
        try await parseRows(into: context, from: csv.rows)
        try await MainActor.run {
            try context.save()
        }
    }
    
    /// Parses rows into an array of books and adds to context
    private static func parseRows(into context: NSManagedObjectContext, from rows: [[String: String]]) async throws -> Void {
        for row in rows {
            // Filter by exclusive shelf
            guard let shelf = row.value(for: .exclusiveShelf),
                  ["currently-reading", "read"].contains(shelf) else {
                continue
            }

            // Check if a book with the same title already exists in the context
            guard let title = row.value(for: .title),
                  let author = row.value(for: .author)?.cleanedWhitespace else {
                continue
            }
            let cleanedTitle = title.lowercased()
            let cleanedAuthor = author.lowercased()

            // Fetch books by author first for efficiency
            let fetchRequest = NSFetchRequest<Book>(entityName: "Book")
            fetchRequest.predicate = NSPredicate(format: "author ==[c] %@", cleanedAuthor)
            let existingBooks = try context.fetch(fetchRequest)

            // Filter for relaxed title match
            let isDuplicate = existingBooks.contains { existingBook in
                guard let existingTitle = existingBook.title?.lowercased() else { return false }
                return cleanedTitle.contains(existingTitle) || existingTitle.contains(cleanedTitle)
            }
            if isDuplicate {
                continue
            }
            
            let isbn = row.value(for: .isbn)?
                 .replacingOccurrences(of: "=\"", with: "")
                 .replacingOccurrences(of: "\"", with: "")
            let rating = row.value(for: .rating).flatMap(Int.init)
            let review = row.value(for: .review)
            let readDateStarted = row.value(for: .dateAdded).flatMap { dateFormatter.date(from: $0) }
            
            // Some books don't have a finished date, just update them to 3 days after added date for simplicity
            let readDateFinished: Date? = {
                if let finished = row.value(for: .dateRead).flatMap({ dateFormatter.date(from: $0) }) {
                    return finished
                } else if let started = readDateStarted {
                    return Calendar.current.date(byAdding: .day, value: 3, to: started)
                } else {
                    return nil
                }
            }()
            let reviewDescription: RichTextDocument? = {
                guard let review, !review.isEmpty else { return nil }
                return RichTextDocument(fromPlainText: review)
            }()
            
            var coverImageUrl: String?
            if let isbn = isbn, !isbn.isEmpty {
                coverImageUrl = try await BookcoverAPIImageURLProvider.url(forISBN: isbn)
            }
            let coverImage: Asset? = {
                guard let coverImageUrl = coverImageUrl else {
                    return nil
                }
                return Asset(context: context, urlString: coverImageUrl)
            }()
            
            
            _ = Book(
                context: context,
                title: title,
                author: author,
                coverImage: coverImage,
                isbn: isbn,
                readDateStarted: readDateStarted,
                readDateFinished: readDateFinished,
                rating: rating,
                reviewDescription: reviewDescription
            )
        }
    }
}
