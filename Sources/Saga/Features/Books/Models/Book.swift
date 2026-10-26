//
//  Book.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import CoreData
import Foundation

/// A simple enum to wrap dates in an enum for status
enum ReadingStatus: String, CaseIterable, Codable, Identifiable {
  case notStarted
  case reading
  case read

  var id: Self { self }

  var title: String {
    switch self {
    case .notStarted: "Want to Read"
    case .reading: "Currently Reading"
    case .read: "Read"
    }
  }

  var shortTitle: String {
    switch self {
    case .notStarted: "Want to Read"
    case .reading: "Reading"
    case .read: "Read"
    }
  }

  init(
    readingStatusRaw: String? = nil,
    readDateStarted: Date?,
    readDateFinished: Date?
  ) {
    if readDateFinished != nil {
      self = .read
    } else if let readingStatusRaw, let status = Self(rawValue: readingStatusRaw) {
      self = status
    } else if readDateStarted != nil {
      self = .reading
    } else {
      self = .notStarted
    }
  }
}

@objc(Book)
final class Book: NSManagedObject {
  static let contentTypeId = "book"

  @NSManaged var id: String
  @NSManaged var updatedAt: Date?
  @NSManaged var createdAt: Date?

  @NSManaged var title: String?
  @NSManaged var isbn: NSNumber?  // 13-digit ISBN13
  @NSManaged var author: String?
  @NSManaged var coverImage: Asset?  // Asset ID for cover image
  @NSManaged var readingStatusRaw: String?
  @NSManaged var readDateStarted: Date?
  @NSManaged var readDateFinished: Date?
  @NSManaged var rating: NSNumber?
  @NSManaged var reviewDescription: RichTextDocument?
  @NSManaged var notes: RichTextDocument?
  @NSManaged var localCoverImageURL: String?

  var readingStatus: ReadingStatus {
    get {
      ReadingStatus(
        readingStatusRaw: readingStatusRaw,
        readDateStarted: readDateStarted,
        readDateFinished: readDateFinished
      )
    }
    set {
      readingStatusRaw = newValue.rawValue
    }
  }

  var displayCoverURL: URL? {
    localCoverImageURL.flatMap(URL.init(string:)) ?? coverImage?.assetURL
  }

  /// Configured fetch request for the sidebar and home book lists that prefetches `coverImage`
  /// and batches faults to avoid N+1 SQLite queries during scrolling and search indexing.
  static func sidebarFetchRequest() -> NSFetchRequest<Book> {
    let request = NSFetchRequest<Book>(entityName: "Book")
    request.sortDescriptors = [
      NSSortDescriptor(keyPath: \Book.readDateStarted, ascending: false)
    ]
    request.relationshipKeyPathsForPrefetching = ["coverImage"]
    request.fetchBatchSize = 100
    return request
  }

  func apply(_ entry: Entry, assetsByID: [String: Asset]) {
    id = entry.id
    createdAt = entry.sys.createdAt
    updatedAt = entry.sys.updatedAt

    let fields = entry.fields
    title = fields.string(at: "title") ?? ""
    author = fields.string(at: "author")
    isbn = fields.int(at: "isbn").map(NSNumber.init(value:))
    rating = fields.int(at: "rating").map(NSNumber.init(value:))
    readDateStarted = Self.parseDate(fields.string(at: "readDateStarted"))
    readDateFinished = Self.parseDate(fields.string(at: "readDateFinished"))
    readingStatus = ReadingStatus(
      readingStatusRaw: fields.string(at: "readingStatus"),
      readDateStarted: readDateStarted,
      readDateFinished: readDateFinished
    )
    reviewDescription = fields["reviewDescription"] as? RichTextDocument
    notes = fields["notes"] as? RichTextDocument
    coverImage = (fields["coverImage"] as? Link).flatMap { assetsByID[$0.id] }
  }

  private static func parseDate(_ raw: String?) -> Date? {
    raw.flatMap {
      try? JSONDecoder.withoutLocalizationContext().decode(Date.self, from: Data("\"\($0)\"".utf8))
    }
  }

  var validRating: Int? {
    guard let value = rating?.intValue, (1...5).contains(value) else { return nil }
    return value
  }

  func toServerUpsertPayload() -> BookServerUpsertPayload? {
    let trimmedTitle = (title ?? "").cleanedWhitespace
    guard !trimmedTitle.isEmpty else { return nil }
    let assetId =
      localCoverImageURL == nil
      ? coverImage?.id.trimmingCharacters(in: .whitespacesAndNewlines)
      : nil
    return BookServerUpsertPayload(
      id: id,
      title: trimmedTitle,
      author: (author ?? "").cleanedWhitespace,
      isbn: isbn?.int64Value,
      rating: validRating,
      readingStatus: readingStatus.rawValue,
      readDateStarted: readDateStarted?.ISO8601Format(),
      readDateFinished: readDateFinished?.ISO8601Format(),
      reviewPlainText: reviewDescription?.nonEmptyPlainText,
      notesPlainText: notes?.nonEmptyPlainText,
      coverAssetId: assetId?.isEmpty == false ? assetId : nil,
      coverImageUrl: GoodreadsSyncService.sanitizedCoverImageURL(localCoverImageURL)
    )
  }

  /// Year of the most recent reading date, used for year search tokens.
  var readYear: Int? {
    (readDateFinished ?? readDateStarted).map { Calendar.current.component(.year, from: $0) }
  }

  var searchDocument: BookSearchDocument {
    BookSearchDocument(
      title: title ?? "",
      author: author ?? "",
      isbn: isbn?.stringValue ?? "",
      review: reviewDescription?.nonEmptyPlainText ?? "",
      notes: notes?.nonEmptyPlainText ?? "",
      rating: validRating,
      status: readingStatus,
      year: readYear
    )
  }
}
