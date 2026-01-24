//
//  GoodreadsCSVParser.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import Foundation
import CoreData
import Contentful
import SwiftCSV
import SwiftUI

private enum BookCSVField: String {
    case title = "Title"
    case author = "Author"
    case isbn = "ISBN13"
    case rating = "My Rating"
    case review = "My Review"
    case dateStarted = "Date Started"
    case dateAdded = "Date Added"
    case dateRead = "Date Read"
    case exclusiveShelf = "Exclusive Shelf"
}

private extension Dictionary where Key == String, Value == String {
    func value(for field: BookCSVField) -> String? {
        self[field.rawValue]
    }
}

private struct DuplicateCandidate {
    let objectID: NSManagedObjectID
    let title: String
}

private struct BookDuplicateIndex {
    let byAuthor: [String: [DuplicateCandidate]]

    func duplicateID(for title: String, author: String) -> NSManagedObjectID? {
        let normalizedAuthor = GoodreadsCSVParser.normalizedAuthor(author)
        guard let candidates = byAuthor[normalizedAuthor] else {
            return nil
        }
        return candidates.first(where: { candidate in
            GoodreadsCSVParser.isDuplicateTitle(title, candidate.title)
        })?.objectID
    }
}

private enum CacheValue<Value> {
    case some(Value)
    case none

    var value: Value? {
        switch self {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }

    init(_ value: Value?) {
        if let value {
            self = .some(value)
        } else {
            self = .none
        }
    }
}

private actor GoodreadsImportCache {
    private var isbnByTitleAuthor: [String: CacheValue<String>] = [:]
    private var isbnTasks: [String: Task<String?, Error>] = [:]

    func storeISBN(_ isbn: String?, forKey key: String) {
        isbnByTitleAuthor[key] = CacheValue(isbn)
    }

    func isbn(
        forKey key: String,
        fetch: @escaping @Sendable () async throws -> String?
    ) async throws -> String? {
        if let cached = isbnByTitleAuthor[key] {
            return cached.value
        }
        if let existingTask = isbnTasks[key] {
            return try await existingTask.value
        }
        let task = Task { try await fetch() }
        isbnTasks[key] = task
        let value = try await task.value
        isbnTasks[key] = nil
        isbnByTitleAuthor[key] = CacheValue(value)
        return value
    }
}

/// Parses a Goodreads export CSV and loads them into CoreData context as Books, merging duplicates
/// as applicable and ensuring as much data is read as possible. Also calls cover image url providers to parse a
/// cover image URL out of the ISBN where possible.
struct GoodreadsCSVParser {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
    
    /// How many rows we parse at once (including making network calls)
    private static let maxConcurrentParses = 10
    
    private static let currentlyReadingShelfName = "currently-reading"
    private static let readShelfName = "read"
    
    /// The only types of Goodread shelves we should parse in
    private static let applicableShelves = [currentlyReadingShelfName, readShelfName]
    
    private init() {}
    
    /// Runs CSV parse from a file URL with a context, then delegates to main to save it
    static func parse(into context: NSManagedObjectContext,
                      from csvFileURL: URL,
                      completedSteps: Binding<Int>,
                      totalSteps: Binding<Int>) async throws -> Void {
        let csv = try NamedCSV(url: csvFileURL)
        let importContext = makeImportContext(from: context)
        try await parseRows(
            into: importContext,
            from: csv.rows,
            completedSteps: completedSteps,
            totalSteps: totalSteps)
        try await importContext.perform {
            if importContext.hasChanges {
                try importContext.save()
            }
        }
        try await context.perform {
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private static func makeImportContext(from context: NSManagedObjectContext) -> NSManagedObjectContext {
        guard let coordinator = context.persistentStoreCoordinator else {
            return context
        }
        let importContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        importContext.persistentStoreCoordinator = coordinator
        importContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        importContext.undoManager = nil
        importContext.name = "Goodreads Import Context"
        return importContext
    }
    
    /// Filters our rows based on a set of criteria so we can operate on as little as possible
    private static func filteredRows(_ rows: [[String: String]]) -> [[String: String]] {
        // Ensure we're only looking at current or past books
        return rows.filter { row in
            guard let shelf = row.value(for: .exclusiveShelf) else {
                return false
            }
            return applicableShelves.contains(shelf)
        }
    }
    
    static func normalizedAuthor(_ author: String) -> String {
        author.cleanedWhitespace.lowercased()
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.cleanedWhitespace.lowercased()
    }

    private static func isbnCacheKey(title: String, author: String) -> String {
        "\(normalizedTitle(title))|\(normalizedAuthor(author))"
    }

    static func isDuplicateTitle(_ title: String, _ existingTitle: String) -> Bool {
        title.localizedCaseInsensitiveContains(existingTitle)
        || existingTitle.localizedCaseInsensitiveContains(title)
    }

    private static func buildDuplicateIndex(
        from context: NSManagedObjectContext,
        rows: [[String: String]]
    ) async throws -> BookDuplicateIndex {
        let normalizedAuthors = Set(
            rows
                .compactMap { $0.value(for: .author)?.cleanedWhitespace }
                .map { normalizedAuthor($0) }
        )
        guard !normalizedAuthors.isEmpty else {
            return BookDuplicateIndex(byAuthor: [:])
        }

        return try await context.perform {
            let fetchRequest = NSFetchRequest<Book>(entityName: "Book")
            fetchRequest.predicate = NSPredicate(format: "author != nil")
            fetchRequest.fetchBatchSize = 200
            let books = try context.fetch(fetchRequest)
            var byAuthor: [String: [DuplicateCandidate]] = [:]
            for book in books {
                guard let author = book.author else { continue }
                let normalized = normalizedAuthor(author)
                guard normalizedAuthors.contains(normalized) else { continue }
                let title = book.title ?? ""
                byAuthor[normalized, default: []].append(
                    DuplicateCandidate(objectID: book.objectID, title: title)
                )
            }
            return BookDuplicateIndex(byAuthor: byAuthor)
        }
    }

    /// Parses rows into an array of books and adds them to context, but doesn't save it
    private static func parseRows(into parentContext: NSManagedObjectContext,
                                  from rows: [[String: String]],
                                  completedSteps: Binding<Int>,
                                  totalSteps: Binding<Int>) async throws {
        let filteredRows = filteredRows(rows)
        await MainActor.run {
            totalSteps.wrappedValue = filteredRows.count
            completedSteps.wrappedValue = 0
        }
        let duplicateIndex = try await buildDuplicateIndex(from: parentContext, rows: filteredRows)
        let lookupCache = GoodreadsImportCache()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = filteredRows.makeIterator()

            func addTask(for row: [String: String]) {
                group.addTask {
                    // Each task gets its own private child context
                    let childContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    childContext.parent = parentContext
                    childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                    childContext.undoManager = nil
                    try await parseRow(
                        row,
                        into: childContext,
                        duplicateIndex: duplicateIndex,
                        lookupCache: lookupCache
                    )
                    try await childContext.perform {
                        if childContext.hasChanges {
                            try childContext.save()
                        }
                    }
                    await MainActor.run {
                        completedSteps.wrappedValue += 1
                    }
                }
            }

            // Start up to maxConcurrentParses
            for _ in 0..<maxConcurrentParses {
                if let row = iterator.next() {
                    addTask(for: row)
                }
            }

            // As each task finishes, start a new one
            while let _ = try await group.next() {
                if let row = iterator.next() {
                    addTask(for: row)
                }
            }
        }
    }



    /// Parses an individual row into a book and adds it into context, but doesn't save it
    private static func parseRow(_ row: [String: String],
                                 into context: NSManagedObjectContext,
                                 duplicateIndex: BookDuplicateIndex,
                                 lookupCache: GoodreadsImportCache) async throws {
        guard let title = row.value(for: .title)?.cleanedWhitespace,
              let author = row.value(for: .author)?.cleanedWhitespace,
              let shelves = row.value(for: .exclusiveShelf) else {
            return
        }
        
        func getISBN() async throws -> NSNumber? {
            let cacheKey = isbnCacheKey(title: title, author: author)
            if let csvIsbnValue = row.value(for: .isbn)?
                .replacingOccurrences(of: "=\"", with: "")
                .replacingOccurrences(of: "\"", with: ""),
               !csvIsbnValue.isEmpty {
                guard let intValue = Int64(csvIsbnValue),
                      intValue > 0 else {
                    return nil
                }
                await lookupCache.storeISBN(csvIsbnValue, forKey: cacheKey)
                return NSNumber(value: intValue)
            } else {
                let isbnStringValue = try await lookupCache.isbn(forKey: cacheKey) {
                    try await OpenLibraryAPIService.isbnFor(title: title, author: author)
                }
                guard let isbnStringValue,
                      !isbnStringValue.isEmpty,
                      let intValue = Int64(isbnStringValue),
                      intValue > 0 else {
                    return nil
                }
                return NSNumber(value: intValue)
            }
        }
        
        let rating = row.value(for: .rating).flatMap { val -> NSNumber? in
            guard !val.isEmpty,
                  let intValue = Int(val),
                  intValue > 0 else { return nil }
            return NSNumber(value: intValue)
        }
        let readDateFinishedFromRead = row.value(for: .dateRead)
            .flatMap { dateFormatter.date(from: $0) }
        let readDateFinishedFromAdded = row.value(for: .dateAdded)
            .flatMap { dateFormatter.date(from: $0) }
        var readDateStarted = row.value(for: .dateStarted)
            .flatMap { dateFormatter.date(from: $0) }
            ?? readDateFinishedFromAdded
        var readDateFinished: Date? = {
            if let readDateFinishedFromRead {
                return readDateFinishedFromRead
            } else if shelves.contains(currentlyReadingShelfName) {
                return nil
            } else {
                return readDateFinishedFromAdded
            }
        }()
        if let finished = readDateFinished, let started = readDateStarted, finished < started {
            print("Warning: read finish before start for \"\(title)\". start=\(started) finish=\(finished)")
            // Create mutable copies we can adjust
            var adjustedStarted: Date? = readDateStarted
            var adjustedFinished: Date? = readDateFinished
            if readDateFinishedFromRead != nil {
                adjustedStarted = nil
            } else {
                adjustedFinished = nil
            }
            // Assign adjusted values back
            readDateStarted = adjustedStarted
            readDateFinished = adjustedFinished
        }
        let reviewDescription: RichTextDocument? = {
            let review = row.value(for: .review)
            guard let review, !review.isEmpty else { return nil }
            return RichTextDocument(fromPlainText: review)
        }()
        
        try await Book.add(
            to: context,
            title: title,
            author: author,
            getISBN: getISBN,
            readDateStarted: readDateStarted,
            readDateFinished: readDateFinished,
            rating: rating,
            reviewDescription: reviewDescription,
            duplicateID: { duplicateIndex.duplicateID(for: title, author: author) }
        )
    }

}
