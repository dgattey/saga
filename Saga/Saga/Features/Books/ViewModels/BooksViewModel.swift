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
@Observable
final class BooksViewModel {
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

  var filteredBooks: [BookSearchResult] = []
  var totalBookCount = 0
  /// Drives the sidebar `.searchable` field and `filteredBooks`.
  var searchModel = SearchViewModel()

  var isSpotlightPresented = false
  private(set) var spotlightResults: [BookSearchResult] = []
  /// Drives the ⌘K Spotlight bar independently of the sidebar filter.
  let spotlightModel = SearchViewModel()
  @ObservationIgnored let sidebarSearchFocusRequests = PassthroughSubject<Void, Never>()

  @ObservationIgnored private var libraryBooks: [Book] = []
  @ObservationIgnored private var isHandlingBookChanges = false
  @ObservationIgnored private var documentCache: [NSManagedObjectID: CachedSearchDocument] = [:]

  var hasActiveSearch: Bool {
    searchModel.hasActiveSearch
  }

  static func bookCountLabel(_ count: Int) -> String {
    count == 1 ? "1 book" : "\(count) books"
  }

  var bookCountText: String {
    let total = Self.bookCountLabel(max(totalBookCount, filteredBooks.count))
    return hasActiveSearch ? "\(filteredBooks.count) of \(total)" : total
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

  func performSearch(with books: FetchedResults<Book>, debounce: Duration? = nil) {
    libraryBooks = sorted(from: books)
    totalBookCount = libraryBooks.count
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
      let aUnfinished = a.readDateFinished == nil
      let bUnfinished = b.readDateFinished == nil
      if aUnfinished != bUnfinished {
        return aUnfinished && !bUnfinished
      }

      let aDate = a.readDateFinished ?? a.readDateStarted ?? .distantPast
      let bDate = b.readDateFinished ?? b.readDateStarted ?? .distantPast
      if aDate != bDate {
        return aDate > bDate
      }

      return (a.title ?? "").localizedCompare(b.title ?? "") == .orderedAscending
    }
  }

  func homeSections(
    for sort: HomeBookSort,
    calendar: Calendar = .current
  ) -> [HomeSection] {
    homeSections(from: filteredBooks.map(\.book), sort: sort, calendar: calendar)
  }

  func homeSections(
    from books: [Book],
    sort: HomeBookSort = .defaultOrder,
    calendar: Calendar = .current
  ) -> [HomeSection] {
    let keepSearchOrder = sort == .defaultOrder && hasActiveSearch && !searchModel.query.isEmpty
    let defaultOrdered = keepSearchOrder ? books : sorted(from: books)
    guard !defaultOrdered.isEmpty else { return [] }

    switch sort {
    case .defaultOrder:
      return [HomeSection(id: "default", title: nil, books: defaultOrdered)]
    case .titleAZ:
      let ordered = defaultOrdered.sorted {
        ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
      }
      return [HomeSection(id: "title", title: nil, books: ordered)]
    case .authorAZ:
      let ordered = defaultOrdered.sorted {
        ($0.author ?? "").localizedStandardCompare($1.author ?? "") == .orderedAscending
      }
      return [HomeSection(id: "author", title: nil, books: ordered)]
    case .byYear:
      let reading = defaultOrdered.filter { $0.readingStatus == .reading }
      let notStarted = defaultOrdered.filter { $0.readingStatus == .notStarted }
      let byYear = Dictionary(grouping: defaultOrdered.filter { $0.readingStatus == .read }) {
        ($0.readDateFinished ?? $0.readDateStarted).map { calendar.component(.year, from: $0) } ?? 0
      }
      var sections: [HomeSection] = []
      if !reading.isEmpty {
        sections.append(
          HomeSection(id: "year.reading", title: ReadingStatus.reading.title, books: reading))
      }
      for year in byYear.keys.sorted(by: >) {
        if year > 0, let group = byYear[year] {
          sections.append(HomeSection(id: "year.\(year)", title: String(year), books: group))
        }
      }
      if !notStarted.isEmpty {
        sections.append(
          HomeSection(
            id: "year.notStarted", title: ReadingStatus.notStarted.title, books: notStarted))
      }
      return sections
    case .byStatus:
      return [ReadingStatus.reading, .notStarted, .read].compactMap { status in
        let group = defaultOrdered.filter { $0.readingStatus == status }
        return group.isEmpty
          ? nil : HomeSection(id: "status.\(status.rawValue)", title: status.title, books: group)
      }
    case .byRating:
      let buckets: [Int?] = [5, 4, 3, 2, 1, nil]
      return buckets.compactMap { stars in
        let group = defaultOrdered.filter { $0.validRating == stars }
        guard !group.isEmpty else { return nil }
        let title = stars.map { String(repeating: "★", count: $0) } ?? "Unrated"
        return HomeSection(id: "rating.\(stars ?? 0)", title: title, books: group)
      }
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
