//
//  BookDetailViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Contentful
import CoreData
import SwiftUI

@Observable
final class BookDetailViewModel {
  enum Field: Hashable {
    case title
    case author
    case isbn
    case review
    case coverURL
    case rating
  }

  var titleDraft: String
  var authorDraft: String
  var isbnDraft: String
  var reviewDraft: String
  var coverURLDraft: String
  var ratingDraft: Int

  @ObservationIgnored private(set) var book: Book
  @ObservationIgnored private var viewContext: NSManagedObjectContext?
  @ObservationIgnored private var lastFocusedField: Field?

  init(book: Book) {
    self.book = book
    self.viewContext = book.managedObjectContext
    self.titleDraft = book.title ?? ""
    self.authorDraft = book.author ?? ""
    self.isbnDraft = book.isbn?.stringValue ?? ""
    self.reviewDraft = book.reviewDescription?.plainText ?? ""
    self.coverURLDraft = book.coverImage?.assetURL?.absoluteString ?? ""
    self.ratingDraft = book.rating?.intValue ?? 0
  }

  var displayTitle: String {
    let normalized = titleDraft.cleanedWhitespace
    return normalized.isEmpty ? "Untitled book" : normalized
  }

  var displayAuthor: String {
    let normalized = authorDraft.cleanedWhitespace
    return normalized.isEmpty ? "Unknown author" : normalized
  }

  func setBook(_ book: Book) {
    guard book.objectID != self.book.objectID else { return }
    self.book = book
    viewContext = book.managedObjectContext
    lastFocusedField = nil
    refreshDraftsFromBook()
  }

  func handleFocusChange(to newValue: Field?) {
    if let lastFocusedField, newValue != lastFocusedField {
      commitField(lastFocusedField)
    }
    lastFocusedField = newValue
  }

  @MainActor
  func updateTitleDraft(_ newValue: String) {
    updateBookDraft { book in
      book.title = newValue.isEmpty ? nil : newValue
    }
  }

  @MainActor
  func updateAuthorDraft(_ newValue: String) {
    updateBookDraft { book in
      book.author = newValue.isEmpty ? nil : newValue
    }
  }

  @MainActor
  func updateISBNDraft(_ newValue: String) {
    let digits = newValue.filter { $0.isNumber }
    let isbnNumber = isbnNumber(from: digits)
    updateBookDraft { book in
      book.isbn = isbnNumber
    }
  }

  @MainActor
  func updateReviewDraft(_ newValue: String) {
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    updateBookDraft { book in
      if trimmed.isEmpty {
        book.reviewDescription = nil
      } else {
        book.reviewDescription = RichTextDocument(fromPlainText: newValue)
      }
    }
  }

  @MainActor
  func updateRatingDraft(_ newValue: Int) {
    ratingDraft = newValue
    updateBookDraft { book in
      book.rating = newValue > 0 ? NSNumber(value: newValue) : nil
    }
    commitRating()
  }

  func commitField(_ field: Field) {
    switch field {
    case .title:
      commitTitle()
    case .author:
      commitAuthor()
    case .isbn:
      commitISBN()
    case .review:
      commitReview()
    case .coverURL:
      commitCoverURL()
    case .rating:
      commitRating()
    }
  }

  private func commitTitle() {
    let normalized = titleDraft.cleanedWhitespace
    updateBook { book in
      book.title = normalized.isEmpty ? nil : normalized
    }
  }

  private func commitAuthor() {
    let normalized = authorDraft.cleanedWhitespace
    updateBook { book in
      book.author = normalized.isEmpty ? nil : normalized
    }
  }

  private func commitISBN() {
    let digits = isbnDraft.filter { $0.isNumber }
    let isbnNumber = isbnNumber(from: digits)
    updateBook { book in
      book.isbn = isbnNumber
    }
    if let isbnNumber {
      isbnDraft = isbnNumber.stringValue
    } else {
      isbnDraft = digits
    }
  }

  private func commitReview() {
    let normalized = reviewDraft.cleanedWhitespace
    let currentReview = reviewDraft
    updateBook { book in
      if normalized.isEmpty {
        book.reviewDescription = nil
      } else {
        book.reviewDescription = RichTextDocument(fromPlainText: currentReview)
      }
    }
  }

  private func commitCoverURL() {
    let currentURL = book.coverImage?.assetURL?.absoluteString ?? ""
    let trimmed = coverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == currentURL {
      return
    }
    let overrideURL = trimmed.isEmpty ? nil : trimmed
    let bookID = book.objectID
    guard let viewContext else { return }
    Task {
      await Book.updateCoverImage(
        for: bookID,
        in: viewContext,
        overrideURL: overrideURL
      )
      saveContextAndSyncBook(bookID: bookID, overrideCoverImageURL: overrideURL)
      await MainActor.run {
        self.coverURLDraft = self.book.coverImage?.assetURL?.absoluteString ?? ""
      }
    }
  }

  private func commitRating() {
    let ratingValue = ratingDraft
    updateBook { book in
      book.rating = ratingValue > 0 ? NSNumber(value: ratingValue) : nil
    }
  }

  private func updateBook(_ update: @escaping (Book) -> Void) {
    guard let viewContext else { return }
    let bookID = book.objectID
    viewContext.perform {
      guard let bookInContext = try? viewContext.existingObject(with: bookID) as? Book else {
        return
      }
      update(bookInContext)
      bookInContext.updatedAt = Date()
      let payload = bookInContext.toServerUpsertPayload()
      do {
        if viewContext.hasChanges {
          try viewContext.save()
        }
      } catch {
        LoggerService.log(
          "Failed to save book edits: \(error)",
          level: .error,
          surface: .persistence
        )
        return
      }
      if let payload {
        Task(priority: .utility) {
          await GoodreadsSyncService.pushBookUpsertIfConfigured(payload)
        }
      }
    }
  }

  @MainActor
  private func updateBookDraft(_ update: @escaping (Book) -> Void) {
    update(book)
    viewContext?.processPendingChanges()
  }

  private func saveContextAndSyncBook(
    bookID: NSManagedObjectID,
    overrideCoverImageURL: String? = nil
  ) {
    guard let viewContext else { return }
    viewContext.perform {
      let payload: BookServerUpsertPayload?
      if let bookInContext = try? viewContext.existingObject(with: bookID) as? Book {
        bookInContext.updatedAt = Date()
        payload = bookInContext.toServerUpsertPayload(
          overrideCoverImageURL: overrideCoverImageURL
        )
      } else {
        payload = nil
      }
      do {
        if viewContext.hasChanges {
          try viewContext.save()
        }
      } catch {
        LoggerService.log(
          "Failed to save book edits: \(error)",
          level: .error,
          surface: .persistence
        )
        return
      }
      if let payload {
        Task(priority: .utility) {
          await GoodreadsSyncService.pushBookUpsertIfConfigured(payload)
        }
      }
    }
  }

  private func refreshDraftsFromBook() {
    titleDraft = book.title ?? ""
    authorDraft = book.author ?? ""
    isbnDraft = book.isbn?.stringValue ?? ""
    reviewDraft = book.reviewDescription?.plainText ?? ""
    coverURLDraft = book.coverImage?.assetURL?.absoluteString ?? ""
    ratingDraft = book.rating?.intValue ?? 0
  }

  private func isbnNumber(from digits: String) -> NSNumber? {
    guard !digits.isEmpty else { return nil }
    if digits.count == 13, let intValue = Int64(digits) {
      return NSNumber(value: intValue)
    }
    if digits.count == 10 {
      let prefix = String(digits.prefix(9))
      let base = "978" + prefix
      guard let checkDigit = isbn13CheckDigit(for: base),
        let intValue = Int64(base + checkDigit)
      else {
        return nil
      }
      return NSNumber(value: intValue)
    }
    return nil
  }

  private func isbn13CheckDigit(for twelveDigits: String) -> String? {
    guard twelveDigits.count == 12,
      twelveDigits.allSatisfy({ $0.isNumber })
    else { return nil }
    var sum = 0
    for (index, char) in twelveDigits.enumerated() {
      guard let digit = char.wholeNumberValue else { return nil }
      sum += (index % 2 == 0) ? digit : digit * 3
    }
    let check = (10 - (sum % 10)) % 10
    return String(check)
  }
}
