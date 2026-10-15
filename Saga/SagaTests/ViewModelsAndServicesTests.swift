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

  @Test("BookDetailViewModel updates drafts, converts ISBN-10 to ISBN-13, and commits to Core Data")
  @MainActor
  func bookDetailViewModelEditsAndCommits() async throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext
    let book = try TestCoreDataStack.makeBook(
      in: context,
      title: "  Initial   Title ",
      author: " Initial  Author ",
      isbn: 9_780_441_478_125,
      rating: 3,
      reviewPlainText: "Initial review"
    )

    let viewModel = BookDetailViewModel(book: book)
    #expect(viewModel.displayTitle == "Initial Title")
    #expect(viewModel.displayAuthor == "Initial Author")

    viewModel.titleDraft = "   "
    #expect(viewModel.displayTitle == "Untitled book")
    viewModel.authorDraft = "   "
    #expect(viewModel.displayAuthor == "Unknown author")

    // Focus transition automatically commits the previously focused field
    viewModel.handleFocusChange(to: .title)
    viewModel.titleDraft = "  Hyperion   Cantos  "
    viewModel.handleFocusChange(to: .author)
    await context.perform {}
    #expect(book.title == "Hyperion Cantos")

    viewModel.authorDraft = "  Dan   Simmons "
    viewModel.handleFocusChange(to: .isbn)
    await context.perform {}
    #expect(book.author == "Dan Simmons")

    // ISBN-10 ("0593135202") converts to ISBN-13 ("9780593135204")
    viewModel.isbnDraft = "0-593-13520-2"
    viewModel.commitField(.isbn)
    await context.perform {}
    #expect(book.isbn?.int64Value == 9_780_593_135_204)
    #expect(viewModel.isbnDraft == "9780593135204")

    viewModel.updateRatingDraft(5)
    viewModel.commitField(.rating)
    await context.perform {}
    #expect(book.rating?.intValue == 5)

    viewModel.reviewDraft = "A classic sci-fi pilgrimage."
    viewModel.commitField(.review)
    await context.perform {}
    #expect(book.reviewDescription?.plainText == "A classic sci-fi pilgrimage.")
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
      SearchHighlightResult(model: book, index: index)
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

  @Test("SearchViewModel highlights character ranges and filters books asynchronously")
  @MainActor
  func searchViewModelHighlightingAndFuzzySearch() async throws {
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

    let searchVM = SearchViewModel()
    let highlighted = searchVM.makeHighlightedAttributedString(
      from: "The Dispossessed",
      ranges: [0...2, 4...15],
      highlightColor: .yellow
    )
    #expect(String(highlighted.characters) == "The Dispossessed")

    searchVM.searchText = "Dispossessed"
    #expect(searchVM.hasActiveSearch)

    let results: [SearchHighlightResult<Book>] = await withCheckedContinuation { continuation in
      searchVM.search(in: [leGuin, butler]) { matched in
        continuation.resume(returning: matched)
      }
    }

    #expect(results.count == 1)
    #expect(results.first?.model.objectID == leGuin.objectID)
    #expect(results.first?.highlighted(for: \BookDTO.title) != nil)
  }
}
