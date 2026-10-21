//
//  BooksViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import Combine
import CoreData
import SwiftUI

/// Contains all our books and allows for filtering
final class BooksViewModel: ObservableObject {
  private struct CachedSearchDocument {
    let bookUpdatedAt: Date?
    let title: String?
    let author: String?
    let isbn: NSNumber?
    let rating: NSNumber?
    let readDateStarted: Date?
    let readDateFinished: Date?
    let document: BookSearchDocument
  }

  @Published var filteredBooks: [BookSearchResult] = []
  /// Drives the sidebar `.searchable` field and `filteredBooks`.
  var searchModel = SearchViewModel()

  @Published var isSpotlightPresented = false
  @Published private(set) var spotlightResults: [BookSearchResult] = []
  /// Drives the ⌘K Spotlight bar independently of the sidebar filter.
  let spotlightModel = SearchViewModel()
  let sidebarSearchFocusRequests = PassthroughSubject<Void, Never>()

  private var libraryBooks: [Book] = []
  private var isHandlingBookChanges = false
  private var documentCache: [NSManagedObjectID: CachedSearchDocument] = [:]
  private var searchModelChanges: AnyCancellable?

  init() {
    searchModelChanges = searchModel.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

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
      documentCache.removeValue(forKey: book.objectID)
    }
    isHandlingBookChanges = true
    performSearch(with: books, debounce: .milliseconds(150))
    DispatchQueue.main.async {
      self.isHandlingBookChanges = false
    }
  }

  func delete(_ book: Book, in context: NSManagedObjectContext) {
    let deletedBookID = book.id
    documentCache.removeValue(forKey: book.objectID)
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
    libraryBooks = sorted(from: books)
    search(libraryBooks, with: searchModel, debounce: debounce) { [weak self] results in
      self?.filteredBooks = results
    }
    if isSpotlightPresented {
      performSpotlightSearch()
    }
  }

  func performSpotlightSearch() {
    search(libraryBooks, with: spotlightModel, debounce: .milliseconds(80)) { [weak self] results in
      self?.spotlightResults = results
    }
  }

  private func search(
    _ books: [Book],
    with model: SearchViewModel,
    debounce: Duration?,
    completion: @escaping ([BookSearchResult]) -> Void
  ) {
    model.search(
      in: books,
      debounce: debounce,
      makeDocuments: { [weak self] in
        self?.cachedDocuments(for: books) ?? books.map(\.searchDocument)
      },
      completion: completion
    )
  }

  private func cachedDocuments(for books: [Book]) -> [BookSearchDocument] {
    if documentCache.count > books.count * 2 {
      documentCache.removeAll(keepingCapacity: true)
    }
    return books.map { book in
      let objectID = book.objectID
      if let cached = documentCache[objectID],
        cached.bookUpdatedAt == book.updatedAt,
        cached.title == book.title,
        cached.author == book.author,
        cached.isbn == book.isbn,
        cached.rating == book.rating,
        cached.readDateStarted == book.readDateStarted,
        cached.readDateFinished == book.readDateFinished
      {
        return cached.document
      }
      let document = book.searchDocument
      documentCache[objectID] = CachedSearchDocument(
        bookUpdatedAt: book.updatedAt,
        title: book.title,
        author: book.author,
        isbn: book.isbn,
        rating: book.rating,
        readDateStarted: book.readDateStarted,
        readDateFinished: book.readDateFinished,
        document: document
      )
      return document
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
      nextBookID = filteredBooks[0].book.objectID

    case .book(let currentID):
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.book.objectID == currentID })
      else {
        nextBookID = filteredBooks[0].book.objectID
        break
      }
      let nextIndex = currentIndex + 1
      guard nextIndex < filteredBooks.count else {
        return .handled
      }
      nextBookID = filteredBooks[nextIndex].book.objectID

    case nil:
      nextBookID = filteredBooks[0].book.objectID
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
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.book.objectID == currentID })
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

      let previousBookID = filteredBooks[currentIndex - 1].book.objectID
      guard entry?.selection != .book(previousBookID) else { return .handled }
      entry = NavigationEntry(selection: .book(previousBookID), scrollContextID: scrollContextID)
      return .handled
    }
  }
}
