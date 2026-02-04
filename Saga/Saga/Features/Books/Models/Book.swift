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

private struct NonSendableBox<T>: @unchecked Sendable {
  let value: T
}

@objc(Book)
final class Book: NSManagedObject, EntryPersistable, SearchableModel, ContentfulSyncable,
  ContentfulVersionTracking
{
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

  /// Tracks whether this book has local changes not yet synced to Contentful
  @NSManaged var isDirty: Bool

  /// The Contentful version number for optimistic locking during two-way sync
  @NSManaged var contentfulVersion: Int

  var readingStatus: ReadingStatus {
    .init(readDateStarted: readDateStarted, readDateFinished: readDateFinished)
  }

  /// Adds a book to context by newly creating it. Automatically handles duplicates. Threadsafe.
  static func add(
    to context: NSManagedObjectContext,
    title: String,
    author: String,
    getISBN: () async throws -> NSNumber?,
    readDateStarted: Date?,
    readDateFinished: Date?,
    rating: NSNumber?,
    reviewDescription: RichTextDocument?,
    duplicateID: (() -> NSManagedObjectID?)? = nil
  ) async throws {
    let prefetchedDuplicateID = duplicateID?()
    let duplicateInfo = try await context.perform {
      let existingBook: Book?
      if let prefetchedDuplicateID,
        let book = try? context.existingObject(with: prefetchedDuplicateID) as? Book
      {
        existingBook = book
      } else {
        existingBook = try findDuplicate(in: context, title: title, author: author)
      }
      let currentISBN = existingBook?.isbn
      let needsCoverImage = existingBook?.coverImage == nil
      return (
        existingBookID: existingBook?.objectID,
        currentISBN: currentISBN,
        needsCoverImage: needsCoverImage
      )
    }

    let isbn: NSNumber?
    if let currentISBN = duplicateInfo.currentISBN {
      isbn = currentISBN
    } else {
      isbn = try await getISBN()
    }

    let coverAsset: Asset?
    if duplicateInfo.needsCoverImage {
      let coverImageURL = await getCoverImageURL(forISBN: isbn, title: title, author: author)
      coverAsset = try await Asset.add(to: context, withURL: coverImageURL)
    } else {
      coverAsset = nil
    }

    // Snapshot non-Sendable values for use inside @Sendable closure
    let reviewDescriptionBox = reviewDescription.map { NonSendableBox(value: $0) }
    let coverAssetID = coverAsset?.objectID

    await context.perform {
      let coverAssetInContext: Asset? = {
        if let coverAssetID {
          return try? context.existingObject(with: coverAssetID) as? Asset
        }
        return nil
      }()
      if let existingBookID = duplicateInfo.existingBookID,
        let existingBook = try? context.existingObject(with: existingBookID) as? Book
      {
        if existingBook.coverImage == nil {
          existingBook.coverImage = coverAssetInContext
        }
        LoggerService.log(
          "Found duplicate \"\(title)\"",
          level: .debug,
          surface: .booksImport
        )
        existingBook.title = title
        existingBook.isbn ??= isbn
        existingBook.readDateFinished ??= readDateFinished
        existingBook.readDateStarted ??= readDateStarted
        existingBook.rating ??= rating
        existingBook.reviewDescription ??= reviewDescriptionBox?.value
      } else {
        _ = Book(
          context: context,
          title: title,
          author: author,
          coverImage: coverAssetInContext,
          isbn: isbn,
          readDateStarted: readDateStarted,
          readDateFinished: readDateFinished,
          rating: rating,
          reviewDescription: reviewDescriptionBox?.value)
      }
    }
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
  private static func findDuplicate(
    in context: NSManagedObjectContext,
    title: String,
    author: String
  ) throws -> Book? {
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
  private static func getOrAddCoverImage(
    to context: NSManagedObjectContext,
    forISBN isbn: NSNumber?,
    andTitle title: String,
    author: String
  ) async throws -> Asset? {
    let fetchTask: Task<String?, Never> = Task.detached(priority: .background) {
      await getCoverImageURL(forISBN: isbn, title: title, author: author)
    }
    let coverImageUrl = await fetchTask.value
    return try await Asset.add(to: context, withURL: coverImageUrl)
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
