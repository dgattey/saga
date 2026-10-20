//
//  BookDraft.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Contentful
import Foundation

/// The local cover override chosen in the editor (`Book.localCoverImageURL`). `none` means the
/// book shows its synced Contentful cover, if it has one.
enum CoverDraft: Equatable {
  case none
  /// A remote `https://` URL or a previously stored local `file://` cover.
  case url(String)
  /// Dropped or pasted image bytes, written to `CoverImageStore` on save.
  case image(Data)

  var urlString: String? {
    if case .url(let urlString) = self { return urlString }
    return nil
  }

  var isEmpty: Bool { self == .none }
}

/// An editable snapshot of a book used by both the edit and create flows. Edits stay here until
/// the user saves, so cancelling never touches Core Data.
struct BookDraft: Equatable {
  enum Issue: Equatable, Identifiable {
    case missingTitle
    case missingAuthor
    case invalidISBN
    case finishedBeforeStarted

    var id: Self { self }

    var message: String {
      switch self {
      case .missingTitle:
        return "Add a title."
      case .missingAuthor:
        return "Add an author."
      case .invalidISBN:
        return "ISBN should be 10 or 13 digits."
      case .finishedBeforeStarted:
        return "The finish date is before the start date."
      }
    }
  }

  var title: String
  var author: String
  var status: ReadingStatus
  /// Backing value for the start date picker; only used for `reading`, or `read` when
  /// `tracksStartDate` is on.
  var startedDate: Date
  /// Backing value for the finish date picker; only used for `read`.
  var finishedDate: Date
  var tracksStartDate: Bool
  /// 0 means unrated.
  var rating: Int
  var isbnText: String
  var reviewText: String
  var cover: CoverDraft

  /// A blank draft for a new book, defaulting to Currently Reading as of today.
  static func empty(now: Date = Date()) -> BookDraft {
    BookDraft(
      title: "",
      author: "",
      status: .reading,
      startedDate: now,
      finishedDate: now,
      tracksStartDate: true,
      rating: 0,
      isbnText: "",
      reviewText: "",
      cover: .none
    )
  }

  init(
    title: String,
    author: String,
    status: ReadingStatus,
    startedDate: Date,
    finishedDate: Date,
    tracksStartDate: Bool,
    rating: Int,
    isbnText: String,
    reviewText: String,
    cover: CoverDraft
  ) {
    self.title = title
    self.author = author
    self.status = status
    self.startedDate = startedDate
    self.finishedDate = finishedDate
    self.tracksStartDate = tracksStartDate
    self.rating = rating
    self.isbnText = isbnText
    self.reviewText = reviewText
    self.cover = cover
  }

  init(book: Book, now: Date = Date()) {
    self.init(
      title: book.title ?? "",
      author: book.author ?? "",
      status: book.readingStatus,
      startedDate: book.readDateStarted ?? book.readDateFinished ?? now,
      finishedDate: book.readDateFinished ?? now,
      tracksStartDate: book.readDateStarted != nil || book.readDateFinished == nil,
      rating: book.rating?.intValue ?? 0,
      isbnText: book.isbn?.stringValue ?? "",
      reviewText: book.reviewDescription?.plainText ?? "",
      cover: book.localCoverImageURL.map(CoverDraft.url) ?? .none
    )
  }

  // MARK: - Derived values

  var normalizedTitle: String { title.cleanedWhitespace }
  var normalizedAuthor: String { author.cleanedWhitespace }

  var readDateStarted: Date? {
    switch status {
    case .notStarted:
      return nil
    case .reading:
      return startedDate
    case .read:
      return tracksStartDate ? startedDate : nil
    }
  }

  var readDateFinished: Date? {
    status == .read ? finishedDate : nil
  }

  var isbn: Int64? { ISBN.isbn13(from: isbnText) }

  var issues: [Issue] {
    var issues: [Issue] = []
    if normalizedTitle.isEmpty {
      issues.append(.missingTitle)
    }
    if normalizedAuthor.isEmpty {
      issues.append(.missingAuthor)
    }
    if !isbnText.cleanedWhitespace.isEmpty, isbn == nil {
      issues.append(.invalidISBN)
    }
    if let readDateStarted, let readDateFinished,
      Calendar.current.startOfDay(for: readDateFinished)
        < Calendar.current.startOfDay(for: readDateStarted)
    {
      issues.append(.finishedBeforeStarted)
    }
    return issues
  }

  var isValid: Bool { issues.isEmpty }

  /// Writes every field except the cover (which `BookMutationService` persists) onto `book`.
  func apply(to book: Book) {
    book.title = normalizedTitle
    book.author = normalizedAuthor
    book.readDateStarted = readDateStarted
    book.readDateFinished = readDateFinished
    book.rating = (1...5).contains(rating) ? NSNumber(value: rating) : nil
    book.isbn = isbn.map { NSNumber(value: $0) }
    let trimmedReview = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedReview.isEmpty {
      book.reviewDescription = nil
    } else if trimmedReview != book.reviewDescription?.plainText {
      book.reviewDescription = RichTextDocument(fromPlainText: trimmedReview)
    }
  }
}
