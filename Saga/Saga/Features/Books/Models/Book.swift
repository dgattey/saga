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
import Ifrit

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
final class Book: NSManagedObject, EntryPersistable, SearchableModel {
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
  /// A cover not yet linked to a Contentful asset (a dropped/pasted image file, or an image
  /// URL). Not part of `fieldMapping`, so Contentful syncs never reset it.
  @NSManaged var localCoverImageURL: String?

  var readingStatus: ReadingStatus {
    .init(readDateStarted: readDateStarted, readDateFinished: readDateFinished)
  }

  /// The cover to render: the local override if set, otherwise the synced cover asset.
  var displayCoverURL: URL? {
    if let localCoverImageURL, let url = URL(string: localCoverImageURL) {
      return url
    }
    return coverImage?.assetURL
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

  /// Creates a `Sendable` snapshot of this book's fields for syncing to `dylangattey.com/api/books/sync`.
  /// Must be called on the book's `NSManagedObjectContext` queue.
  ///
  /// Covers synced from Contentful are referenced by asset ID only, so unchanged covers aren't
  /// re-uploaded on every edit. A pending local cover sends its URL (when it's on an allowlisted
  /// host) so the server can upload and link a new asset. `file://` covers send neither here;
  /// `BookMutationService.sync(_:)` attaches their compressed bytes before pushing.
  func toServerUpsertPayload() -> BookServerUpsertPayload? {
    let trimmedTitle = (title ?? "").cleanedWhitespace
    guard !trimmedTitle.isEmpty else { return nil }
    let trimmedAuthor = (author ?? "").cleanedWhitespace
    let contentfulCoverAssetId: String? = {
      guard localCoverImageURL == nil, let coverImage, coverImage.isContentfulManaged else {
        return nil
      }
      let assetId = coverImage.id.trimmingCharacters(in: .whitespacesAndNewlines)
      return assetId.isEmpty ? nil : assetId
    }()
    let localCoverURL = GoodreadsSyncService.sanitizedCoverImageURL(localCoverImageURL)
    let ratingInt: Int? = {
      guard let value = rating?.intValue, (1...5).contains(value) else { return nil }
      return value
    }()
    let reviewText = reviewDescription?.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    return BookServerUpsertPayload(
      id: id,
      title: trimmedTitle,
      author: trimmedAuthor,
      isbn: isbn?.int64Value,
      rating: ratingInt,
      readDateStarted: readDateStarted?.ISO8601Format(),
      readDateFinished: readDateFinished?.ISO8601Format(),
      reviewPlainText: reviewText?.isEmpty == false ? reviewText : nil,
      coverAssetId: contentfulCoverAssetId,
      coverImageUrl: localCoverURL
    )
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
      reviewDescription: self.reviewDescription?.plainText
    )
  }
}

final class BookDTO: SearchableDTO, CustomStringConvertible, @unchecked Sendable {
  let id: String
  let title: String?
  let isbn: String?
  let author: String?
  let coverImage: AssetDTO?
  let readDateStarted: String?
  let readDateFinished: String?
  let rating: String?
  let reviewDescription: String?
  let fuzzySearchableProperties: [FuseProp]

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

    var props: [FuseProp] = [
      FuseProp(title ?? ""),
      FuseProp(isbn ?? ""),
      FuseProp(author ?? ""),
      FuseProp(readDateStarted ?? ""),
      FuseProp(readDateFinished ?? ""),
      FuseProp(rating ?? ""),
      FuseProp(reviewDescription ?? ""),
    ]
    if let coverImage {
      props.append(contentsOf: coverImage.fuzzySearchableProperties)
    }
    self.fuzzySearchableProperties = props
  }

  var description: String {
    return self.title ?? "Untitled BookDTO"
  }

  static var nestedSearchableDTOKeyPaths: [PartialKeyPath<BookDTO>] = [
    \BookDTO.coverImage
  ]

  static var fuzzySearchKeyPaths: [PartialKeyPath<BookDTO>] = [
    \BookDTO.title,
    \BookDTO.isbn,
    \BookDTO.author,
    \BookDTO.readDateStarted,
    \BookDTO.readDateFinished,
    \BookDTO.rating,
    \BookDTO.reviewDescription,
  ]
}
