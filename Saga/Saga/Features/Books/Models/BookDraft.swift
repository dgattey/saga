//
//  BookDraft.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Contentful
import Foundation

enum ISBN {
  static func isbn13(from raw: String) -> Int64? {
    let chars = raw.uppercased().filter { $0.isNumber || $0 == "X" }
    if chars.count == 13, chars.allSatisfy(\.isNumber) {
      return Int64(chars)
    }
    guard chars.count == 10,
      chars.prefix(9).allSatisfy(\.isNumber),
      let last = chars.last, last.isNumber || last == "X"
    else { return nil }
    let base = "978" + chars.prefix(9)
    var sum = 0
    for (index, char) in base.enumerated() {
      guard let digit = char.wholeNumberValue else { return nil }
      sum += index.isMultiple(of: 2) ? digit : digit * 3
    }
    return Int64("\(base)\((10 - (sum % 10)) % 10)")
  }
}

enum CoverDraft: Equatable {
  case none
  case url(String)
  case image(Data)

  var urlString: String? {
    if case .url(let urlString) = self { return urlString }
    return nil
  }

  var isEmpty: Bool { self == .none }
}

struct BookDraft: Equatable {
  enum Issue: Equatable, Identifiable {
    case missingTitle
    case missingAuthor
    case invalidISBN
    case finishedBeforeStarted

    var id: Self { self }

    var message: String {
      switch self {
      case .missingTitle: "Add a title."
      case .missingAuthor: "Add an author."
      case .invalidISBN: "ISBN should be 10 or 13 digits."
      case .finishedBeforeStarted: "The finish date is before the start date."
      }
    }
  }

  var title = ""
  var author = ""
  var status: ReadingStatus = .reading
  var startedDate = Date()
  var finishedDate = Date()
  var tracksStartDate = true
  var rating = 0
  var isbnText = ""
  var reviewText = ""
  var notesText = ""
  var cover: CoverDraft = .none

  static func empty(now: Date = Date()) -> BookDraft {
    BookDraft(startedDate: now, finishedDate: now)
  }

  var normalizedTitle: String { title.cleanedWhitespace }
  var normalizedAuthor: String { author.cleanedWhitespace }

  var readDateStarted: Date? {
    switch status {
    case .notStarted: nil
    case .reading: startedDate
    case .read: tracksStartDate ? startedDate : nil
    }
  }

  var readDateFinished: Date? {
    status == .read ? finishedDate : nil
  }

  var isbn: Int64? { ISBN.isbn13(from: isbnText) }

  var issues: [Issue] {
    var issues: [Issue] = []
    if normalizedTitle.isEmpty { issues.append(.missingTitle) }
    if normalizedAuthor.isEmpty { issues.append(.missingAuthor) }
    if !isbnText.cleanedWhitespace.isEmpty, isbn == nil { issues.append(.invalidISBN) }
    if let readDateStarted, let readDateFinished,
      Calendar.current.startOfDay(for: readDateFinished)
        < Calendar.current.startOfDay(for: readDateStarted)
    {
      issues.append(.finishedBeforeStarted)
    }
    return issues
  }

  var isValid: Bool { issues.isEmpty }

  func apply(to book: Book) {
    book.title = normalizedTitle
    book.author = normalizedAuthor
    book.readDateStarted = readDateStarted
    book.readDateFinished = readDateFinished
    book.rating = (1...5).contains(rating) ? NSNumber(value: rating) : nil
    book.isbn = isbn.map { NSNumber(value: $0) }
    book.reviewDescription = Self.updatedRichText(for: reviewText, existing: book.reviewDescription)
    book.notes = Self.updatedRichText(for: notesText, existing: book.notes)
  }

  private static func updatedRichText(
    for text: String,
    existing: RichTextDocument?
  ) -> RichTextDocument? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed == existing?.plainText ? existing : RichTextDocument(fromPlainText: trimmed)
  }
}

extension BookDraft {
  init(book: Book, now: Date = Date()) {
    self.init(
      title: book.title ?? "",
      author: book.author ?? "",
      status: book.readingStatus,
      startedDate: book.readDateStarted ?? book.readDateFinished ?? now,
      finishedDate: book.readDateFinished ?? now,
      tracksStartDate: book.readDateStarted != nil || book.readDateFinished == nil,
      rating: book.validRating ?? 0,
      isbnText: book.isbn?.stringValue ?? "",
      reviewText: book.reviewDescription?.plainText ?? "",
      notesText: book.notes?.plainText ?? "",
      cover: book.localCoverImageURL.map(CoverDraft.url) ?? .none
    )
  }
}
