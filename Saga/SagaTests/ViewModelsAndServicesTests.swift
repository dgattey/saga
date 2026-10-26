//
//  ViewModelsAndServicesTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

import CoreData
import Foundation
import SwiftUI
import Testing

import class Contentful.RichTextDocument

@testable import Saga

@Suite("ViewModels, Navigation, Search & RichText")
struct ViewModelsAndServicesTests {
  @Test("String.cleanedWhitespace collapses runs of whitespace and newlines")
  func stringCleanedWhitespace() {
    #expect("  Hello   \n\t  world  ".cleanedWhitespace == "Hello world")
    #expect("   \n\t  ".cleanedWhitespace == "")
  }

  @Test("RichTextDocument plainText, attributedString, and ValueTransformer round-trip")
  func richTextDocumentRoundTrip() throws {
    RichTextDocumentTransformer.register()
    let doc = RichTextDocument(fromPlainText: "First paragraph<br>Second line\r\n\r\nThird")
    #expect(doc.plainText == "First paragraph\n\nSecond line\n\nThird")

    let attributed = try #require(doc.attributedString)
    #expect(attributed.string == "First paragraph\n\nSecond line\n\nThird")

    let customTransformer = RichTextToAttributedStringTransformer(
      baseFont: PlatformFont.systemFont(ofSize: 16),
      baseColor: labelColor
    )
    let customAttributed = customTransformer.attributedString(from: doc)
    #expect(customAttributed.string == "First paragraph\n\nSecond line\n\nThird")

    let transformer = RichTextDocumentTransformer()
    let data = try #require(transformer.transformedValue(doc) as? Data)
    let decoded = try #require(transformer.reverseTransformedValue(data) as? RichTextDocument)
    #expect(decoded.plainText == doc.plainText)
  }

  @Test("BooksViewModel sorts unfinished books first, then by most recent date, then by title")
  @MainActor
  func booksViewModelSortingAndKeyboardNavigation() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let olderFinished = try TestCoreDataStack.makeBook(
      in: context,
      title: "Foundation",
      readDateStarted: Date(timeIntervalSince1970: 1_600_000_000),
      readDateFinished: Date(timeIntervalSince1970: 1_600_500_000)
    )
    let newerFinishedB = try TestCoreDataStack.makeBook(
      in: context,
      title: "Children of Time",
      readDateStarted: Date(timeIntervalSince1970: 1_700_000_000),
      readDateFinished: Date(timeIntervalSince1970: 1_700_500_000)
    )
    let newerFinishedA = try TestCoreDataStack.makeBook(
      in: context,
      title: "Ancillary Justice",
      readDateStarted: Date(timeIntervalSince1970: 1_700_000_000),
      readDateFinished: Date(timeIntervalSince1970: 1_700_500_000)
    )
    let currentlyReading = try TestCoreDataStack.makeBook(
      in: context,
      title: "Exhalation",
      readDateStarted: Date(timeIntervalSince1970: 1_650_000_000),
      readDateFinished: nil
    )

    let viewModel = BooksViewModel()
    let sorted = viewModel.sorted(
      from: [olderFinished, newerFinishedB, newerFinishedA, currentlyReading]
    )
    #expect(
      sorted.map(\.objectID) == [
        currentlyReading.objectID,
        newerFinishedA.objectID,
        newerFinishedB.objectID,
        olderFinished.objectID,
      ])

    viewModel.filteredBooks = sorted.enumerated().map { index, book in
      BookSearchResult(book: book, index: index)
    }

    let initialContextID = UUID()
    var entry: NavigationEntry? = NavigationEntry(
      selection: .home(lastSelectedBookID: nil),
      scrollContextID: initialContextID
    )

    // Down from Home -> first book, preserving scrollContextID
    #expect(viewModel.navigateToNextBook(entry: &entry) == .handled)
    #expect(entry?.selection == .book(currentlyReading.objectID))
    #expect(entry?.scrollContextID == initialContextID)

    // Down again -> second book
    #expect(viewModel.navigateToNextBook(entry: &entry) == .handled)
    #expect(entry?.selection == .book(newerFinishedA.objectID))

    // Up -> back to first book
    #expect(viewModel.navigateToPreviousBook(entry: &entry) == .handled)
    #expect(entry?.selection == .book(currentlyReading.objectID))

    // Up from first book -> back to Home preserving lastSelectedBookID
    #expect(viewModel.navigateToPreviousBook(entry: &entry) == .handled)
    #expect(entry?.selection == .home(lastSelectedBookID: currentlyReading.objectID))

    // Up while already at Home -> ignored
    #expect(viewModel.navigateToPreviousBook(entry: &entry) == .ignored)
  }

  @Test("Held arrow keys stop at the last book going down and return to Home going up")
  @MainActor
  func booksViewModelKeyRepeatNavigation() throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let books = try (0..<5).map { index in
      try TestCoreDataStack.makeBook(in: context, title: "Book \(index)", coverURLString: nil)
    }
    let viewModel = BooksViewModel()
    viewModel.filteredBooks = books.enumerated().map { index, book in
      BookSearchResult(book: book, index: index)
    }
    var entry: NavigationEntry? = NavigationEntry(selection: .home(lastSelectedBookID: nil))

    for _ in 0..<10 {
      #expect(viewModel.navigateToNextBook(entry: &entry) == .handled)
    }
    #expect(entry?.selection == .book(books[4].objectID))

    for _ in 0..<5 {
      #expect(viewModel.navigateToPreviousBook(entry: &entry) == .handled)
    }
    #expect(entry?.selection == .home(lastSelectedBookID: books[0].objectID))
    for _ in 0..<5 {
      #expect(viewModel.navigateToPreviousBook(entry: &entry) == .ignored)
    }
  }

  @Test("NavigationHistory tracks back/forward stacks, observers, and home scroll cloning")
  @MainActor
  func navigationHistoryBackForwardAndCloning() throws {
    let container = TestCoreDataStack.makeContainer()
    let book1 = try TestCoreDataStack.makeBook(in: container.viewContext, title: "Book 1")
    let book2 = try TestCoreDataStack.makeBook(in: container.viewContext, title: "Book 2")

    let homeID = UUID()
    let history = NavigationHistory(initialHomeScrollContextID: homeID)
    let homeEntry = NavigationEntry(
      selection: .home(lastSelectedBookID: nil),
      scrollContextID: homeID
    )
    let book1Entry = NavigationEntry(selection: .book(book1.objectID))
    let book2Entry = NavigationEntry(selection: .book(book2.objectID))

    var currentEntry: NavigationEntry? = homeEntry
    history.onNavigationChange(from: nil, to: homeEntry)
    #expect(!history.canGoBack)

    currentEntry = book1Entry
    history.onNavigationChange(from: homeEntry, to: book1Entry)
    #expect(history.canGoBack)
    #expect(!history.canGoForward)

    currentEntry = book2Entry
    history.onNavigationChange(from: book1Entry, to: book2Entry)
    #expect(history.backStack.count == 2)

    let binding = Binding<NavigationEntry?>(
      get: { currentEntry },
      set: { newValue in
        let oldValue = currentEntry
        currentEntry = newValue
        history.onNavigationChange(from: oldValue, to: newValue)
      }
    )

    history.goBack(entry: binding)
    #expect(currentEntry == book1Entry)
    #expect(history.lastSelectionChangeWasHistory)
    #expect(history.canGoForward)

    history.goForward(entry: binding)
    #expect(currentEntry == book2Entry)
    #expect(!history.canGoForward)

    let scrollStore = ScrollPositionStore()
    let scrollKey = ScrollKey(scope: .home, region: "main", contextID: homeID)
    scrollStore.update(240.0, for: scrollKey)

    let newHomeEntry = history.makeHomeEntry(
      currentEntry: currentEntry,
      scrollStore: scrollStore,
      cloneFromLast: true
    )
    #expect(newHomeEntry.selection == .home(lastSelectedBookID: book2.objectID))
    let clonedKey = ScrollKey(scope: .home, region: "main", contextID: newHomeEntry.scrollContextID)
    #expect(scrollStore.position(for: clonedKey) == 240.0)
  }

  @Test("SearchViewModel searches books asynchronously and suggests tokens from the last word")
  @MainActor
  func searchViewModelSearchAndSuggestions() async throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext
    let leGuin = try TestCoreDataStack.makeBook(
      in: context,
      title: "The Dispossessed",
      author: "Ursula K. Le Guin"
    )
    let butler = try TestCoreDataStack.makeBook(
      in: context,
      title: "Parable of the Sower",
      author: "Octavia E. Butler"
    )

    let books = [leGuin, butler]
    let searchVM = SearchViewModel()
    searchVM.searchText = "Dispossessed"
    #expect(searchVM.hasActiveSearch)

    let results: [BookSearchResult] = await withCheckedContinuation { continuation in
      searchVM.search(
        in: books,
        makeDocuments: { books.map(\.searchDocument) },
        completion: { continuation.resume(returning: $0) }
      )
    }

    #expect(results.count == 1)
    #expect(results.first?.book.objectID == leGuin.objectID)
    #expect(results.first?.match.titleRanges == [4..<16])

    searchVM.searchText = "parable re"
    searchVM.search(in: books, makeDocuments: { books.map(\.searchDocument) }, completion: { _ in })
    #expect(searchVM.suggestedTokens == [.status(.read), .status(.reading), .hasReview])

    searchVM.tokens.append(.status(.read))
    #expect(searchVM.searchText == "parable ")
    #expect(searchVM.key == SearchViewModel.Key(text: "parable ", tokens: [.status(.read)]))
  }

  @Test("BooksViewModel formats book counts and sorts/groups Home sections across all modes")
  @MainActor
  func booksViewModelHomeSectionsAndCounts() throws {
    #expect(BooksViewModel.bookCountLabel(0) == "0 books")
    #expect(BooksViewModel.bookCountLabel(1) == "1 book")
    #expect(BooksViewModel.bookCountLabel(142) == "142 books")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    func makeDate(year: Int, month: Int, day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let readingBook = try TestCoreDataStack.makeBook(
      in: context,
      title: "Exhalation",
      author: "Ted Chiang",
      rating: nil,
      readDateStarted: makeDate(year: 2026, month: 3, day: 10),
      readDateFinished: nil
    )
    let wantToReadBook = try TestCoreDataStack.makeBook(
      in: context,
      title: "Dune",
      author: "Frank Herbert",
      rating: nil,
      readDateStarted: nil,
      readDateFinished: nil
    )
    let read2026Later = try TestCoreDataStack.makeBook(
      in: context,
      title: "Children of Time",
      author: "Adrian Tchaikovsky",
      rating: 5,
      readDateStarted: makeDate(year: 2026, month: 2, day: 1),
      readDateFinished: makeDate(year: 2026, month: 2, day: 14)
    )
    let read2026Earlier = try TestCoreDataStack.makeBook(
      in: context,
      title: "Ancillary Justice",
      author: "Ann Leckie",
      rating: 4,
      readDateStarted: makeDate(year: 2026, month: 1, day: 2),
      readDateFinished: makeDate(year: 2026, month: 1, day: 12)
    )
    let read2025 = try TestCoreDataStack.makeBook(
      in: context,
      title: "Foundation",
      author: "Isaac Asimov",
      rating: 5,
      readDateStarted: makeDate(year: 2025, month: 6, day: 1),
      readDateFinished: makeDate(year: 2025, month: 6, day: 10)
    )

    let allBooks = [read2025, wantToReadBook, read2026Earlier, readingBook, read2026Later]
    let viewModel = BooksViewModel()
    viewModel.totalBookCount = 142
    viewModel.filteredBooks = allBooks.enumerated().map {
      BookSearchResult(book: $1, index: $0)
    }
    #expect(viewModel.bookCountText == "142 books")
    viewModel.searchModel.searchText = "sci"
    #expect(viewModel.bookCountText == "5 of 142 books")
    viewModel.searchModel.searchText = ""

    let defaultSections = viewModel.homeSections(
      from: allBooks,
      sort: .defaultOrder,
      calendar: calendar
    )
    #expect(defaultSections.count == 1)
    #expect(defaultSections[0].headerText == nil)
    #expect(
      defaultSections[0].books.map(\.objectID) == [
        readingBook.objectID,
        wantToReadBook.objectID,
        read2026Later.objectID,
        read2026Earlier.objectID,
        read2025.objectID,
      ]
    )

    let titleSections = viewModel.homeSections(from: allBooks, sort: .titleAZ, calendar: calendar)
    #expect(titleSections.count == 1)
    #expect(titleSections[0].headerText == nil)
    #expect(
      titleSections[0].books.map { $0.title ?? "" } == [
        "Ancillary Justice",
        "Children of Time",
        "Dune",
        "Exhalation",
        "Foundation",
      ]
    )

    let authorSections = viewModel.homeSections(from: allBooks, sort: .authorAZ, calendar: calendar)
    #expect(authorSections.count == 1)
    #expect(authorSections[0].headerText == nil)
    #expect(
      authorSections[0].books.map { $0.author ?? "" } == [
        "Adrian Tchaikovsky",
        "Ann Leckie",
        "Frank Herbert",
        "Isaac Asimov",
        "Ted Chiang",
      ]
    )

    let yearSections = viewModel.homeSections(from: allBooks, sort: .byYear, calendar: calendar)
    #expect(
      yearSections.map(\.headerText) == [
        "Currently Reading · 1 book",
        "2026 · 2 books",
        "2025 · 1 book",
        "Want to Read · 1 book",
      ]
    )
    #expect(
      yearSections[1].books.map(\.objectID) == [
        read2026Later.objectID,
        read2026Earlier.objectID,
      ]
    )

    let statusSections = viewModel.homeSections(from: allBooks, sort: .byStatus, calendar: calendar)
    #expect(
      statusSections.map(\.headerText) == [
        "Currently Reading · 1 book",
        "Want to Read · 1 book",
        "Read · 3 books",
      ]
    )

    let ratingSections = viewModel.homeSections(from: allBooks, sort: .byRating, calendar: calendar)
    #expect(
      ratingSections.map(\.headerText) == [
        "★★★★★ · 2 books",
        "★★★★ · 1 book",
        "Unrated · 2 books",
      ]
    )
  }
}
