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
  private static let coverImageURLCache = CoverImageURLCache()

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

  var readingStatus: ReadingStatus {
    .init(readDateStarted: readDateStarted, readDateFinished: readDateFinished)
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

  /// Returns the best cover image URL without creating an Asset.
  static func bestCoverImageURL(
    forISBN isbn: NSNumber?,
    title: String,
    author: String
  ) async -> String? {
    await getCoverImageURL(forISBN: isbn, title: title, author: author)
  }

  /// Helper method to get cover image URL without creating Asset
  private static func getCoverImageURL(
    forISBN isbn: NSNumber?,
    title: String,
    author: String
  ) async -> String? {
    guard !PersistenceService.isRunningUnitTests else { return nil }
    guard let isbn = isbn?.stringValue else {
      do {
        return try await OpenLibraryAPIService.coverImageURL(forTitle: title, author: author)
      } catch {
        return nil
      }
    }
    return await coverImageURLCache.value(forISBN: isbn) {
      do {
        let openLibraryCandidate = try await OpenLibraryAPIService.bestCoverCandidate(
          forISBN: isbn,
          title: title,
          author: author
        )
        let shouldCheckBookcover: Bool = {
          guard let openLibraryCandidate else { return true }
          return openLibraryCandidate.bytes < CoverSelection.openLibraryPreferBookcoverBelowBytes
        }()
        let bookcoverCandidate =
          shouldCheckBookcover
          ? try await BookcoverAPIService.coverImageCandidate(forISBN: isbn)
          : nil
        let preferredCandidate = preferredCoverCandidate(
          openLibrary: openLibraryCandidate,
          bookcover: bookcoverCandidate
        )
        return preferredCandidate?.url
      } catch {
        return nil
      }
    }
  }

  /// Updates the cover image for a book, using either an override URL or a fallback lookup.
  static func updateCoverImage(
    for bookID: NSManagedObjectID,
    in context: NSManagedObjectContext,
    overrideURL: String?
  ) async {
    let trimmedOverride = overrideURL?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedOverride = trimmedOverride?.isEmpty == true ? nil : trimmedOverride
    let bookInfo = await context.perform {
      guard let book = try? context.existingObject(with: bookID) as? Book else {
        return nil as (isbn: NSNumber?, title: String, author: String)?
      }
      return (isbn: book.isbn, title: book.title ?? "", author: book.author ?? "")
    }
    guard let bookInfo else { return }

    let resolvedURL: String?
    if let normalizedOverride {
      resolvedURL = normalizedOverride
    } else {
      resolvedURL = await bestCoverImageURL(
        forISBN: bookInfo.isbn,
        title: bookInfo.title,
        author: bookInfo.author
      )
    }

    let asset = try? await Asset.add(to: context, withURL: resolvedURL)
    let assetID = asset?.objectID

    await context.perform {
      guard let book = try? context.existingObject(with: bookID) as? Book else {
        return
      }
      let assetInContext: Asset? = {
        if let assetID {
          return try? context.existingObject(with: assetID) as? Asset
        }
        return nil
      }()
      book.coverImage = assetInContext
    }
  }

  private enum CoverSelection {
    static let openLibraryPreferBookcoverBelowBytes = 80_000
    static let bookcoverPreferredMinBytes = 30_000
    static let bookcoverPreferredRatio = 0.85
  }

  private static func preferredCoverCandidate(
    openLibrary: CoverImageCandidate?,
    bookcover: CoverImageCandidate?
  ) -> CoverImageCandidate? {
    guard let openLibrary else {
      return bookcover
    }
    guard let bookcover else {
      return openLibrary
    }
    if bookcover.bytes >= CoverSelection.bookcoverPreferredMinBytes,
      Double(bookcover.bytes) >= Double(openLibrary.bytes) * CoverSelection.bookcoverPreferredRatio
    {
      return bookcover
    }
    return openLibrary.bytes >= bookcover.bytes ? openLibrary : bookcover
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
  func toServerUpsertPayload(overrideCoverImageURL: String? = nil) -> BookServerUpsertPayload? {
    let trimmedTitle = (title ?? "").cleanedWhitespace
    guard !trimmedTitle.isEmpty else { return nil }
    let trimmedAuthor = (author ?? "").cleanedWhitespace
    let rawCoverURL = overrideCoverImageURL ?? coverImage?.urlString
    let sanitizedCoverURL = GoodreadsSyncService.sanitizedCoverImageURL(rawCoverURL)
    let existingCoverAssetId: String? = {
      guard let assetId = coverImage?.id.trimmingCharacters(in: .whitespacesAndNewlines),
        !assetId.isEmpty
      else {
        return nil
      }
      return assetId
    }()
    let ratingInt: Int? = {
      guard let value = rating?.intValue, (1...5).contains(value) else { return nil }
      return value
    }()
    return BookServerUpsertPayload(
      id: id,
      title: trimmedTitle,
      author: trimmedAuthor,
      isbn: isbn?.int64Value,
      rating: ratingInt,
      readDateStarted: readDateStarted?.ISO8601Format(),
      readDateFinished: readDateFinished?.ISO8601Format(),
      reviewPlainText: reviewDescription?.plainText,
      coverAssetId: existingCoverAssetId,
      coverImageUrl: sanitizedCoverURL
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

private actor CoverImageURLCache {
  private var values: [String: CacheValue<String>] = [:]
  private var tasks: [String: Task<String?, Never>] = [:]

  func value(forISBN isbn: String, fetch: @escaping @Sendable () async -> String?) async -> String?
  {
    if let cached = values[isbn] {
      return cached.value
    }
    if let existingTask = tasks[isbn] {
      return await existingTask.value
    }
    let task = Task { await fetch() }
    tasks[isbn] = task
    let value = await task.value
    tasks[isbn] = nil
    values[isbn] = CacheValue(value)
    return value
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
