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
    case dateAdded = "Date Added"
    case dateRead = "Date Read"
    case exclusiveShelf = "Exclusive Shelf"
}

private extension Dictionary where Key == String, Value == String {
    func value(for field: BookCSVField) -> String? {
        self[field.rawValue]
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
        try await parseRows(
            into: context,
            from: csv.rows,
            completedSteps: completedSteps,
            totalSteps: totalSteps)
        try await MainActor.run {
            try context.save()
        }
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
    
    /// Parses rows into an array of books and adds them to context, but doesn't save it
    private static func parseRows(into parentContext: NSManagedObjectContext,
                                  from rows: [[String: String]],
                                  completedSteps: Binding<Int>,
                                  totalSteps: Binding<Int>) async throws {
        let filteredRows = filteredRows(rows)
        totalSteps.wrappedValue = filteredRows.count
        completedSteps.wrappedValue = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = filteredRows.makeIterator()
            var activeTasks = 0

            func addNextTask() {
                if let row = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        defer { activeTasks -= 1 }
                        // Each task gets its own private child context
                        let childContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                        childContext.parent = parentContext
                        try await parseRow(row, into: childContext)
                        try await childContext.perform {
                            if childContext.hasChanges {
                                try childContext.save()
                            }
                        }
                        completedSteps.wrappedValue += 1
                    }
                }
            }

            // Start up to maxConcurrentParses
            for _ in 0..<maxConcurrentParses {
                addNextTask()
            }

            // As each task finishes, start a new one
            while activeTasks > 0 {
                try await group.next()
                addNextTask()
            }
        }
    }



    /// Parses an individual row into a book and adds it into context, but doesn't save it
    private static func parseRow(_ row: [String: String], into context: NSManagedObjectContext) async throws {
        guard let title = row.value(for: .title)?.cleanedWhitespace,
              let author = row.value(for: .author)?.cleanedWhitespace,
              let shelves = row.value(for: .exclusiveShelf) else {
            return
        }
        
        func getISBN() async throws -> NSNumber? {
            let isbnStringValue: String?
            if let csvIsbnValue = row.value(for: .isbn)?
                .replacingOccurrences(of: "=\"", with: "")
                .replacingOccurrences(of: "\"", with: ""),
               !csvIsbnValue.isEmpty {
                isbnStringValue = csvIsbnValue
            } else {
                isbnStringValue = try await OpenLibraryAPIService.isbnFor(title: title, author: author)
            }
            guard let isbnStringValue = isbnStringValue,
                  !isbnStringValue.isEmpty,
                  let intValue = Int64(isbnStringValue),
                  intValue > 0 else {
                return nil
            }
            return NSNumber(value: intValue)
        }
        
        let rating = row.value(for: .rating).flatMap { val -> NSNumber? in
            guard !val.isEmpty,
                  let intValue = Int(val),
                  intValue > 0 else { return nil }
            return NSNumber(value: intValue)
        }
        let readDateStarted = row.value(for: .dateAdded).flatMap { dateFormatter.date(from: $0) }
        let readDateFinished: Date? = {
            print(title, applicableShelves)
            if shelves.contains(currentlyReadingShelfName) {
                return nil
            } else if let finished = row.value(for: .dateRead).flatMap({ dateFormatter.date(from: $0) }) {
                return finished
            } else if let started = readDateStarted {
                return Calendar.current.date(byAdding: .day, value: 3, to: started)
            } else {
                return nil
            }
        }()
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
            reviewDescription: reviewDescription
        )
    }

}
