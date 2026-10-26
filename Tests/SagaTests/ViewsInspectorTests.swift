//
//  ViewsInspectorTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

import CoreData
import SwiftUI
import Testing
import ViewInspector

@testable import Saga

@Suite("SwiftUI Component Views (ViewInspector)")
struct ViewsInspectorTests {
  @Test("StarRatingView renders filled and empty stars and updates binding on tap")
  @MainActor
  func starRatingViewInspection() throws {
    let displayOnly = StarRatingView(rating: 3, maxRating: 5)
    let hStack = try displayOnly.inspect().hStack()
    let forEach = try hStack.forEach(0)
    #expect(forEach.count == 5)
    #expect(try forEach.image(0).actualImage().name() == "star.fill")
    #expect(try forEach.image(2).actualImage().name() == "star.fill")
    #expect(try forEach.image(3).actualImage().name() == "star")
    #expect(try forEach.image(4).actualImage().name() == "star")

    var currentRating = 2
    let binding = Binding(get: { currentRating }, set: { currentRating = $0 })
    let interactive = StarRatingView(rating: binding, maxRating: 5)
    let interactiveForEach = try interactive.inspect().hStack().forEach(0)
    try interactiveForEach.button(3).tap()
    #expect(currentRating == 4)
  }

  @Test("BookStatusView renders reading icon only when book is currently being read")
  @MainActor
  func bookStatusViewInspection() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let readingBook = try TestCoreDataStack.makeBook(
      in: context,
      title: "Reading Now",
      readDateStarted: Date(),
      readDateFinished: nil
    )
    let finishedBook = try TestCoreDataStack.makeBook(
      in: context,
      title: "Finished Book",
      readDateStarted: Date(),
      readDateFinished: Date()
    )

    let readingView = BookStatusView(book: readingBook)
    let image = try readingView.inspect().image()
    #expect(try image.actualImage().name() == "bookmark.circle.fill")

    let finishedView = BookStatusView(book: finishedBook)
    #expect(throws: Never.self) {
      _ = try finishedView.inspect().emptyView()
    }
  }

  @Test("BookListHeaderView and BookListEmptyStateView render expected copy")
  @MainActor
  func bookListHeaderAndEmptyStateInspection() throws {
    var didRequestNewBook = false
    let header = BookListHeaderView(onNewBook: { didRequestNewBook = true })
    #expect(try header.inspect().hStack().text(0).string() == "Books")
    try header.inspect().hStack().button(2).tap()
    #expect(didRequestNewBook)

    let empty = BookListEmptyStateView()
    #expect(try empty.inspect().text().string() == "No results")
  }

  @Test("BookCoverActionBar labels Auto-Find for new books and routes each action")
  @MainActor
  func bookCoverActionBarInspection() throws {
    var actions: [String] = []
    let creatingBar = BookCoverActionBar(
      isCreating: true,
      isSearching: false,
      onFind: { actions.append("find") },
      onPaste: { actions.append("paste") },
      onChooseFile: { actions.append("file") },
      onEnterURL: { actions.append("url") }
    )
    let inspected = try creatingBar.inspect()
    for title in ["Auto-Find", "Paste", "File…", "URL…"] {
      try inspected.find(text: title).find(ViewType.Button.self, relation: .parent).tap()
    }
    #expect(actions == ["find", "paste", "file", "url"])

    let editingBar = BookCoverActionBar(
      isCreating: false,
      isSearching: false,
      onFind: {},
      onPaste: {},
      onChooseFile: {},
      onEnterURL: {}
    )
    #expect(try editingBar.inspect().find(text: "Find").string() == "Find")
  }

  @Test("Editorial labels and the empty notes prompt render their copy")
  @MainActor
  func editorialLabelInspection() throws {
    let labeled = EditorialLabeledValue(label: "Started") {
      Text("Feb 2, 2026")
    }
    #expect(try labeled.inspect().find(text: "STARTED").string() == "STARTED")
    #expect(try labeled.inspect().find(text: "Feb 2, 2026").string() == "Feb 2, 2026")

    let reviewLabel = try EditorialSectionLabel("Review").inspect()
    #expect(try reviewLabel.find(text: "REVIEW").string() == "REVIEW")

    let emptyNotes = try BookNotesEmptyState().inspect()
    #expect(try emptyNotes.find(text: "PRIVATE NOTES").string() == "PRIVATE NOTES")
    #expect(
      try emptyNotes.find(text: "No notes yet. Choose Edit to add your thoughts.").string()
        == "No notes yet. Choose Edit to add your thoughts."
    )
  }

  @Test("CacheLimitRow formats limits and usage for display")
  @MainActor
  func cacheLimitRowFormatting() {
    #expect(CacheLimitRow.formatLimit(0) == "Unlimited")
    #expect(CacheLimitRow.formatLimit(0.5) == "500 MB")
    #expect(CacheLimitRow.formatLimit(5) == "5 GB")
    #expect(CacheLimitRow.limitOptions.contains(5))
  }

  @Test("HomeSidebarRow renders Home label and triggers makeHomeEntry when not on Home")
  @MainActor
  func homeSidebarRowInspection() throws {
    let container = TestCoreDataStack.makeContainer()
    let book = try TestCoreDataStack.makeBook(in: container.viewContext)

    var currentEntry: NavigationEntry? = NavigationEntry(selection: .book(book.objectID))
    let expectedHomeEntry = NavigationEntry(
      selection: .home(lastSelectedBookID: book.objectID)
    )
    var didCallMakeHome = false

    let row = HomeSidebarRow(
      entry: Binding(get: { currentEntry }, set: { currentEntry = $0 }),
      makeHomeEntry: {
        didCallMakeHome = true
        return expectedHomeEntry
      }
    )

    let inspected = try row.environment(AnimationSettings.shared).inspect()
    #expect(try inspected.find(text: "Home").string() == "Home")
    #expect(!didCallMakeHome)
  }

  @Test("NowReadingBarView renders active book metadata and invokes onSelect on tap")
  @MainActor
  func nowReadingBarViewInspection() throws {
    let container = TestCoreDataStack.makeContainer()
    let book = try TestCoreDataStack.makeBook(
      in: container.viewContext,
      title: "Exhalation",
      author: "Ted Chiang",
      readDateStarted: Date(),
      readDateFinished: nil
    )

    var didSelect = false
    let bar = NowReadingBarView(book: book) {
      didSelect = true
    }
    let inspected = try bar.inspect()
    #expect(try inspected.find(text: "Currently reading").string() == "Currently reading")
    #expect(try inspected.find(text: "Exhalation").string() == "Exhalation")
    #expect(try inspected.find(text: "Ted Chiang").string() == "Ted Chiang")
    try inspected.find(ViewType.Button.self).tap()
    #expect(didSelect)
  }

  @Test("HomeView and HomeBooksSectionView render counts, sort menu, and sections")
  @MainActor
  func homeViewAndSectionGroupingInspection() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let date2026 =
      calendar.date(from: DateComponents(year: 2026, month: 2, day: 14, hour: 12)) ?? Date()
    let date2025 =
      calendar.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 12)) ?? Date()

    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext
    let readingBook = try TestCoreDataStack.makeBook(
      in: context,
      title: "Exhalation",
      author: "Ted Chiang",
      rating: nil,
      readDateStarted: date2026,
      readDateFinished: nil
    )
    let finished2026 = try TestCoreDataStack.makeBook(
      in: context,
      title: "Ancillary Justice",
      author: "Ann Leckie",
      rating: 5,
      readDateStarted: date2026,
      readDateFinished: date2026
    )
    let finished2025 = try TestCoreDataStack.makeBook(
      in: context,
      title: "Foundation",
      author: "Isaac Asimov",
      rating: 4,
      readDateStarted: date2025,
      readDateFinished: date2025
    )
    let undatedRead = try TestCoreDataStack.makeBook(
      in: context,
      title: "The Outsiders",
      author: "S.E. Hinton",
      rating: 4,
      readingStatus: .read,
      readDateStarted: nil,
      readDateFinished: nil
    )

    let inspectedUndatedDetails = try BookReadDetailsView(book: undatedRead).inspect()
    #expect(try inspectedUndatedDetails.find(text: "Read").string() == "Read")

    let viewModel = BooksViewModel()
    viewModel.totalBookCount = 142
    let books = [readingBook, finished2026, finished2025, undatedRead]
    viewModel.filteredBooks = books.enumerated().map {
      BookSearchResult(book: $1, index: $0)
    }
    var currentEntry: NavigationEntry? = NavigationEntry(selection: .home(lastSelectedBookID: nil))
    let entryBinding = Binding(get: { currentEntry }, set: { currentEntry = $0 })

    let homeView = HomeView(entry: entryBinding)
      .environment(viewModel)
      .environment(ScrollPositionStore())
    let inspectedHome = try homeView.inspect()
    #expect(try inspectedHome.find(text: "Books").string() == "Books")
    #expect(try inspectedHome.find(text: "142 books").string() == "142 books")
    for option in HomeBookSort.allCases {
      #expect(try inspectedHome.find(text: option.title).string() == option.title)
    }

    let defaultSection = HomeBooksSectionView(entry: entryBinding, sort: .defaultOrder)
      .environment(viewModel)
    let inspectedDefault = try defaultSection.inspect()
    #expect(inspectedDefault.findAll(ViewType.Section.self).isEmpty)
    #expect(inspectedDefault.findAll(HomeBookThumbnailView.self).count == 4)

    let titleSection = HomeBooksSectionView(entry: entryBinding, sort: .titleAZ)
      .environment(viewModel)
    let inspectedTitle = try titleSection.inspect()
    #expect(inspectedTitle.findAll(ViewType.Section.self).isEmpty)
    let titleThumbnails = inspectedTitle.findAll(HomeBookThumbnailView.self)
    #expect(
      try titleThumbnails.map { try $0.actualView().book.title ?? "" } == [
        "Ancillary Justice",
        "Exhalation",
        "Foundation",
        "The Outsiders",
      ]
    )

    let yearSection = HomeBooksSectionView(entry: entryBinding, sort: .byYear)
      .environment(viewModel)
    let inspectedYear = try yearSection.inspect()
    #expect(inspectedYear.findAll(ViewType.Section.self).count == 4)
    #expect(
      try inspectedYear.find(text: "Currently Reading · 1 book").string()
        == "Currently Reading · 1 book"
    )
    #expect(try inspectedYear.find(text: "2026 · 1 book").string() == "2026 · 1 book")
    #expect(try inspectedYear.find(text: "2025 · 1 book").string() == "2025 · 1 book")
    #expect(try inspectedYear.find(text: "Earlier · 1 book").string() == "Earlier · 1 book")

    let statusSection = HomeBooksSectionView(entry: entryBinding, sort: .byStatus)
      .environment(viewModel)
    let inspectedStatus = try statusSection.inspect()
    #expect(inspectedStatus.findAll(ViewType.Section.self).count == 2)
    #expect(try inspectedStatus.find(text: "Read · 3 books").string() == "Read · 3 books")

    let ratingSection = HomeBooksSectionView(entry: entryBinding, sort: .byRating)
      .environment(viewModel)
    let inspectedRating = try ratingSection.inspect()
    #expect(inspectedRating.findAll(ViewType.Section.self).count == 3)
    #expect(try inspectedRating.find(text: "★★★★★ · 1 book").string() == "★★★★★ · 1 book")
    #expect(try inspectedRating.find(text: "★★★★ · 2 books").string() == "★★★★ · 2 books")
    #expect(try inspectedRating.find(text: "Unrated · 1 book").string() == "Unrated · 1 book")
  }
}
