//
//  HomeBookSort.swift
//  Saga
//
//  Created by Dylan Gattey on 10/26/26.
//

import Foundation

/// A section of books displayed when the Home grid is in a grouped sort mode.
struct HomeBookGroup: Identifiable {
  let id: String
  let title: String
  let books: [BookSearchResult]

  var count: Int {
    books.count
  }

  var countText: String {
    HomeBookSort.bookCountLabel(for: books.count)
  }

  var headerText: String {
    "\(title) · \(countText)"
  }
}

/// Controls how books on the Home feed are sorted and optionally grouped into sections.
enum HomeBookSort: String, CaseIterable, Identifiable, Sendable {
  case defaultOrder = "default"
  case byYear = "year"
  case byStatus = "status"
  case byRating = "rating"
  case titleAZ = "title"
  case authorAZ = "author"

  static let storageKey = "home.bookSort"

  var id: Self { self }

  var title: String {
    switch self {
    case .defaultOrder: "Default"
    case .byYear: "By Year"
    case .byStatus: "By Status"
    case .byRating: "By Rating"
    case .titleAZ: "Title A–Z"
    case .authorAZ: "Author A–Z"
    }
  }

  var systemImage: String {
    switch self {
    case .defaultOrder: "clock"
    case .byYear: "calendar"
    case .byStatus: "bookmark"
    case .byRating: "star"
    case .titleAZ: "textformat.abc"
    case .authorAZ: "person"
    }
  }

  /// Whether this sort mode renders section headers above grouped grids.
  var isGrouped: Bool {
    switch self {
    case .defaultOrder, .titleAZ, .authorAZ:
      false
    case .byYear, .byStatus, .byRating:
      true
    }
  }

  // MARK: - Count Formatting

  static func bookCountLabel(for count: Int) -> String {
    count == 1 ? "1 book" : "\(count) books"
  }

  static func headerCountLabel(
    filteredCount: Int,
    totalCount: Int,
    isFiltered: Bool
  ) -> String {
    let resolvedTotal = max(totalCount, filteredCount)
    guard isFiltered else {
      return bookCountLabel(for: resolvedTotal)
    }
    return "\(filteredCount) of \(bookCountLabel(for: resolvedTotal))"
  }

  // MARK: - Comparators

  /// Unfinished books at the top, then date descending, then title comparison.
  static func compareDefault(_ a: Book, _ b: Book) -> Bool {
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

  /// Alphabetical title comparison (empty titles last), tie-breaking with the default sort.
  static func compareTitle(_ a: Book, _ b: Book) -> Bool {
    let aTitle = (a.title ?? "").cleanedWhitespace
    let bTitle = (b.title ?? "").cleanedWhitespace
    if aTitle.isEmpty != bTitle.isEmpty {
      return !aTitle.isEmpty
    }
    let order = aTitle.localizedStandardCompare(bTitle)
    if order != .orderedSame {
      return order == .orderedAscending
    }
    return compareDefault(a, b)
  }

  /// Alphabetical author comparison (empty authors last), tie-breaking by title.
  static func compareAuthor(_ a: Book, _ b: Book) -> Bool {
    let aAuthor = (a.author ?? "").cleanedWhitespace
    let bAuthor = (b.author ?? "").cleanedWhitespace
    if aAuthor.isEmpty != bAuthor.isEmpty {
      return !aAuthor.isEmpty
    }
    let order = aAuthor.localizedStandardCompare(bAuthor)
    if order != .orderedSame {
      return order == .orderedAscending
    }
    return compareTitle(a, b)
  }

  static func normalizedRating(for book: Book) -> Int? {
    guard let value = book.rating?.intValue, (1...5).contains(value) else { return nil }
    return value
  }

  // MARK: - Sorting & Grouping

  /// Returns books in a flat order for this sort mode.
  func sortedResults(
    from results: [BookSearchResult],
    calendar: Calendar = .current
  ) -> [BookSearchResult] {
    switch self {
    case .defaultOrder:
      return results.sorted { Self.compareDefault($0.book, $1.book) }
    case .titleAZ:
      return results.sorted { Self.compareTitle($0.book, $1.book) }
    case .authorAZ:
      return results.sorted { Self.compareAuthor($0.book, $1.book) }
    case .byYear, .byStatus, .byRating:
      return groups(from: results, calendar: calendar).flatMap(\.books)
    }
  }

  /// Returns grouped sections for grouped sort modes, or an empty array for flat sort modes.
  func groups(
    from results: [BookSearchResult],
    calendar: Calendar = .current
  ) -> [HomeBookGroup] {
    switch self {
    case .defaultOrder, .titleAZ, .authorAZ:
      return []
    case .byYear:
      return yearGroups(from: results, calendar: calendar)
    case .byStatus:
      return statusGroups(from: results)
    case .byRating:
      return ratingGroups(from: results)
    }
  }

  private func yearGroups(
    from results: [BookSearchResult],
    calendar: Calendar
  ) -> [HomeBookGroup] {
    var reading: [BookSearchResult] = []
    var byFinishedYear: [Int: [BookSearchResult]] = [:]
    var notStarted: [BookSearchResult] = []

    for result in results {
      switch result.book.readingStatus {
      case .reading:
        reading.append(result)
      case .read:
        if let date = result.book.readDateFinished ?? result.book.readDateStarted {
          let year = calendar.component(.year, from: date)
          byFinishedYear[year, default: []].append(result)
        } else {
          notStarted.append(result)
        }
      case .notStarted:
        notStarted.append(result)
      }
    }

    var sections: [HomeBookGroup] = []
    if !reading.isEmpty {
      sections.append(
        HomeBookGroup(
          id: "year.reading",
          title: ReadingStatus.reading.title,
          books: reading.sorted { Self.compareDefault($0.book, $1.book) }
        )
      )
    }
    for year in byFinishedYear.keys.sorted(by: >) {
      guard let yearBooks = byFinishedYear[year], !yearBooks.isEmpty else { continue }
      sections.append(
        HomeBookGroup(
          id: "year.\(year)",
          title: String(year),
          books: yearBooks.sorted { Self.compareDefault($0.book, $1.book) }
        )
      )
    }
    if !notStarted.isEmpty {
      sections.append(
        HomeBookGroup(
          id: "year.notStarted",
          title: ReadingStatus.notStarted.title,
          books: notStarted.sorted { Self.compareTitle($0.book, $1.book) }
        )
      )
    }
    return sections
  }

  private func statusGroups(from results: [BookSearchResult]) -> [HomeBookGroup] {
    let orderedStatuses: [ReadingStatus] = [.reading, .notStarted, .read]
    return orderedStatuses.compactMap { status in
      let matching =
        results
        .filter { $0.book.readingStatus == status }
        .sorted { Self.compareDefault($0.book, $1.book) }
      guard !matching.isEmpty else { return nil }
      return HomeBookGroup(
        id: "status.\(status.rawValue)",
        title: status.title,
        books: matching
      )
    }
  }

  private func ratingGroups(from results: [BookSearchResult]) -> [HomeBookGroup] {
    var sections: [HomeBookGroup] = []
    for stars in (1...5).reversed() {
      let matching =
        results
        .filter { Self.normalizedRating(for: $0.book) == stars }
        .sorted { Self.compareDefault($0.book, $1.book) }
      guard !matching.isEmpty else { continue }
      sections.append(
        HomeBookGroup(
          id: "rating.\(stars)",
          title: String(repeating: "★", count: stars),
          books: matching
        )
      )
    }
    let unrated =
      results
      .filter { Self.normalizedRating(for: $0.book) == nil }
      .sorted { Self.compareDefault($0.book, $1.book) }
    if !unrated.isEmpty {
      sections.append(
        HomeBookGroup(
          id: "rating.unrated",
          title: "Unrated",
          books: unrated
        )
      )
    }
    return sections
  }
}
