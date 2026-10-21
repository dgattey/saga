//
//  Book.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Contentful
import ContentfulPersistence
import CoreData
import Foundation

/// A simple enum to wrap dates in an enum for status
enum ReadingStatus: String, CaseIterable, Identifiable {
  case notStarted
  case reading
  case read

  var id: Self { self }

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
final class Book: NSManagedObject, EntryPersistable {
  static let contentTypeId = "book"

  @NSManaged var id: String
  @NSManaged var localeCode: String?
  @NSManaged var updatedAt: Date?
  @NSManaged var createdAt: Date?

  @NSManaged var title: String?
  @NSManaged var isbn: NSNumber?  // 13-digit ISBN13
  @NSManaged var author: String?
  @NSManaged var coverImage: Asset?  // Asset ID for cover image
  @NSManaged var readDateStarted: Date?
  @NSManaged var readDateFinished: Date?
  @NSManaged var rating: NSNumber?
  @NSManaged var reviewDescription: RichTextDocument?
  @NSManaged var localCoverImageURL: String?

  var readingStatus: ReadingStatus {
    .init(readDateStarted: readDateStarted, readDateFinished: readDateFinished)
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

  static func fieldMapping() -> [Contentful.FieldName: String] {
    return [
      "title": "title",
      "isbn": "isbn",
      "author": "author",
      "coverImage": "coverImage",
      "readDateStarted": "readDateStarted",
      "readDateFinished": "readDateFinished",
      "rating": "rating",
      "reviewDescription": "reviewDescription",
    ]
  }

  func toServerUpsertPayload() -> BookServerUpsertPayload? {
    let trimmedTitle = (title ?? "").cleanedWhitespace
    guard !trimmedTitle.isEmpty else { return nil }
    let assetId =
      localCoverImageURL == nil && coverImage?.isContentfulManaged == true
      ? coverImage?.id.trimmingCharacters(in: .whitespacesAndNewlines)
      : nil
    let ratingValue = rating?.intValue
    let reviewText = reviewDescription?.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    return BookServerUpsertPayload(
      id: id,
      title: trimmedTitle,
      author: (author ?? "").cleanedWhitespace,
      isbn: isbn?.int64Value,
      rating: ratingValue.flatMap { (1...5).contains($0) ? $0 : nil },
      readDateStarted: readDateStarted?.ISO8601Format(),
      readDateFinished: readDateFinished?.ISO8601Format(),
      reviewPlainText: reviewText?.isEmpty == false ? reviewText : nil,
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
      review: reviewDescription?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      rating: rating?.intValue,
      status: readingStatus,
      year: readYear
    )
  }
}
