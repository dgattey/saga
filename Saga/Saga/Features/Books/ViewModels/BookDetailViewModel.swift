//
//  BookDetailViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Combine
import Contentful
import CoreData
import SwiftUI

final class BookDetailViewModel: ObservableObject {
  enum Field: Hashable {
    case title
    case author
    case isbn
    case review
    case coverURL
    case rating
  }

  @Published var titleDraft: String
  @Published var authorDraft: String
  @Published var isbnDraft: String
  @Published var reviewDraft: String
  @Published var coverURLDraft: String
  @Published var ratingDraft: Int

  private(set) var book: Book
  private var viewContext: NSManagedObjectContext?
  private var lastFocusedField: Field?
  private var cancellables: Set<AnyCancellable> = []

  init(book: Book) {
    self.book = book
    self.viewContext = book.managedObjectContext
    self.titleDraft = book.title ?? ""
    self.authorDraft = book.author ?? ""
    self.isbnDraft = book.isbn?.stringValue ?? ""
    self.reviewDraft = book.reviewDescription?.attributedString?.string ?? ""
    self.coverURLDraft = book.coverImage?.assetURL?.absoluteString ?? ""
    self.ratingDraft = book.rating?.intValue ?? 0
    observeBookChanges()
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
    observeBookChanges()
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
      saveContextIfNeeded()
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
      guard viewContext.hasChanges else { return }
      do {
        try viewContext.save()
      } catch {
        LoggerService.log(
          "Failed to save book edits: \(error)",
          level: .error,
          surface: .persistence
        )
      }
    }
  }

  @MainActor
  private func updateBookDraft(_ update: @escaping (Book) -> Void) {
    update(book)
    viewContext?.processPendingChanges()
  }

  private func saveContextIfNeeded() {
    guard let viewContext else { return }
    viewContext.perform {
      guard viewContext.hasChanges else { return }
      do {
        try viewContext.save()
      } catch {
        LoggerService.log(
          "Failed to save book edits: \(error)",
          level: .error,
          surface: .persistence
        )
      }
    }
  }

  private func refreshDraftsFromBook() {
    titleDraft = book.title ?? ""
    authorDraft = book.author ?? ""
    isbnDraft = book.isbn?.stringValue ?? ""
    reviewDraft = book.reviewDescription?.attributedString?.string ?? ""
    coverURLDraft = book.coverImage?.assetURL?.absoluteString ?? ""
    ratingDraft = book.rating?.intValue ?? 0
  }

  private func observeBookChanges() {
    cancellables.removeAll()
    book.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
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
