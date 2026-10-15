//
//  BooksViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import CoreData
import SwiftUI

/// Contains all our books and allows for filtering
final class BooksViewModel: ObservableObject {
  private struct CachedBookDTO {
    let bookUpdatedAt: Date?
    let coverUpdatedAt: Date?
    let title: String?
    let author: String?
    let isbn: NSNumber?
    let rating: NSNumber?
    let readDateStarted: Date?
    let readDateFinished: Date?
    let dto: BookDTO
  }

  @Published var filteredBooks: [SearchHighlightResult<Book>] = []
  @Published var searchModel = SearchViewModel()
  private var isHandlingBookChanges = false
  private var dtoCache: [NSManagedObjectID: CachedBookDTO] = [:]

  var hasActiveSearch: Bool {
    searchModel.hasActiveSearch
  }

  func refreshSearch(for books: FetchedResults<Book>) {
    performSearch(
      with: books,
      debounce: searchModel.hasActiveSearch ? .milliseconds(200) : nil
    )
  }

  func handleBooksChange(_ books: FetchedResults<Book>) {
    performSearch(with: books, debounce: .milliseconds(150))
  }

  func handleBooksChangeNotification(_ notification: Notification, books: FetchedResults<Book>) {
    guard !isHandlingBookChanges else { return }
    guard let userInfo = notification.userInfo else { return }
    let updated = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
    let inserted = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
    let refreshed = (userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject>) ?? []
    let deleted = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []
    let changed = updated.union(inserted).union(refreshed).union(deleted)
    let changedBooks = changed.compactMap { $0 as? Book }
    guard !changedBooks.isEmpty else { return }
    for book in changedBooks {
      dtoCache.removeValue(forKey: book.objectID)
    }
    isHandlingBookChanges = true
    performSearch(with: books, debounce: .milliseconds(150))
    DispatchQueue.main.async {
      self.isHandlingBookChanges = false
    }
  }

  func delete(_ book: Book, in context: NSManagedObjectContext) {
    let deletedBookID = book.id
    dtoCache.removeValue(forKey: book.objectID)
    withAnimation {
      context.delete(book)
      do {
        try context.save()
      } catch {
        let nsError = error as NSError
        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
      }
    }
    Task(priority: .utility) {
      await GoodreadsSyncService.pushBookDeletionIfConfigured(id: deletedBookID)
    }
  }

  func performSearch(with books: FetchedResults<Book>, debounce: Duration? = nil) {
    let sortedBooks = sorted(from: books)
    searchModel.search(
      in: sortedBooks,
      debounce: debounce,
      makeDTOs: { [weak self] in
        guard let self else { return sortedBooks.map { $0.toDTO() } }
        return self.cachedDTOs(for: sortedBooks)
      },
      completion: { results in
        self.filteredBooks = results
      }
    )
  }

  private func cachedDTOs(for books: [Book]) -> [BookDTO] {
    if dtoCache.count > books.count * 2 {
      dtoCache.removeAll(keepingCapacity: true)
    }
    return books.map { book in
      let objectID = book.objectID
      let bookUpdatedAt = book.updatedAt
      let coverUpdatedAt = book.coverImage?.updatedAt
      if let cached = dtoCache[objectID],
        cached.bookUpdatedAt == bookUpdatedAt,
        cached.coverUpdatedAt == coverUpdatedAt,
        cached.title == book.title,
        cached.author == book.author,
        cached.isbn == book.isbn,
        cached.rating == book.rating,
        cached.readDateStarted == book.readDateStarted,
        cached.readDateFinished == book.readDateFinished
      {
        return cached.dto
      }
      let dto = book.toDTO()
      dtoCache[objectID] = CachedBookDTO(
        bookUpdatedAt: bookUpdatedAt,
        coverUpdatedAt: coverUpdatedAt,
        title: book.title,
        author: book.author,
        isbn: book.isbn,
        rating: book.rating,
        readDateStarted: book.readDateStarted,
        readDateFinished: book.readDateFinished,
        dto: dto
      )
      return dto
    }
  }

  /// Unfinished books at the top, then date descending with either finished or start, then title comparison. Most recent first.
  func sorted(from books: FetchedResults<Book>) -> [Book] {
    sorted(from: Array(books))
  }

  /// Unfinished books at the top, then date descending with either finished or start, then title comparison. Most recent first.
  func sorted<S: Sequence>(from books: S) -> [Book] where S.Element == Book {
    return books.sorted { a, b in
      // 1. Unfinished books come first
      let aUnfinished = a.readDateFinished == nil
      let bUnfinished = b.readDateFinished == nil
      if aUnfinished != bUnfinished {
        return aUnfinished && !bUnfinished
      }

      // 2. Use the most recent of `readDateFinished` or `readDateStarted`
      let aDate = a.readDateFinished ?? a.readDateStarted ?? .distantPast
      let bDate = b.readDateFinished ?? b.readDateStarted ?? .distantPast
      if aDate != bDate {
        return aDate > bDate  // More recent first
      }

      // 3. Tie-breaker: localized title comparison
      return (a.title ?? "").localizedCompare(b.title ?? "") == .orderedAscending
    }
  }

  // MARK: - Keyboard Navigation

  /// Moves selection to the next book in `filteredBooks`, or to the first book when starting from Home / no selection.
  @discardableResult
  func navigateToNextBook(entry: inout NavigationEntry?) -> KeyPress.Result {
    guard !filteredBooks.isEmpty else { return .ignored }

    let nextBookID: NSManagedObjectID

    switch entry?.selection {
    case .home:
      nextBookID = filteredBooks[0].model.objectID

    case .book(let currentID):
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.model.objectID == currentID })
      else {
        nextBookID = filteredBooks[0].model.objectID
        break
      }
      let nextIndex = currentIndex + 1
      guard nextIndex < filteredBooks.count else {
        return .handled
      }
      nextBookID = filteredBooks[nextIndex].model.objectID

    case nil:
      nextBookID = filteredBooks[0].model.objectID
    }

    guard entry?.selection != .book(nextBookID) else { return .handled }
    let scrollContextID = entry?.scrollContextID ?? UUID()
    entry = NavigationEntry(selection: .book(nextBookID), scrollContextID: scrollContextID)
    return .handled
  }

  /// Moves selection to the previous book in `filteredBooks`, or back to Home when at the first book.
  @discardableResult
  func navigateToPreviousBook(entry: inout NavigationEntry?) -> KeyPress.Result {
    guard !filteredBooks.isEmpty else { return .ignored }

    switch entry?.selection {
    case .home, nil:
      return .ignored

    case .book(let currentID):
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.model.objectID == currentID })
      else {
        return .ignored
      }

      let scrollContextID = entry?.scrollContextID ?? UUID()
      if currentIndex == 0 {
        let homeSelection =
          entry?.selection.homeSelectionPreservingLast()
          ?? .home(lastSelectedBookID: currentID)
        entry = NavigationEntry(selection: homeSelection, scrollContextID: scrollContextID)
        return .handled
      }

      let previousBookID = filteredBooks[currentIndex - 1].model.objectID
      guard entry?.selection != .book(previousBookID) else { return .handled }
      entry = NavigationEntry(selection: .book(previousBookID), scrollContextID: scrollContextID)
      return .handled
    }
  }
}
