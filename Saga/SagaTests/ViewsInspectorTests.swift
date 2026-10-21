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

    let emptyNotes = try BookNotesEmptyState().inspect()
    #expect(try emptyNotes.find(text: "NOTES").string() == "NOTES")
    #expect(
      try emptyNotes.find(text: "No notes yet. Choose Edit to add your thoughts.").string()
        == "No notes yet. Choose Edit to add your thoughts."
    )
  }

  @Test("CacheLimitRow formats limits and usage for display")
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

    let inspected = try row.environmentObject(AnimationSettings.shared).inspect()
    #expect(try inspected.find(text: "Home").string() == "Home")
    #expect(!didCallMakeHome)
  }

  @Test("SettingsPane exposes expected metadata for all settings categories")
  func settingsPaneMetadataInspection() {
    #expect(SettingsPane.allCases == [.general, .storage, .credits, .about])
    #expect(SettingsPane.allCases.map(\.title) == ["General", "Storage", "Credits", "About"])
    for pane in SettingsPane.allCases {
      #expect(!pane.systemImage.isEmpty)
      #expect(pane.id == pane.rawValue)
    }
  }

  @Test("CreditItem and QuickLinkItem datasets contain expected APIs, libraries, and URLs")
  func creditItemDatasetInspection() {
    let quickLinkTitles = QuickLinkItem.all.map(\.title)
    #expect(quickLinkTitles == ["Website", "GitHub", "More by Dylan"])
    #expect(QuickLinkItem.all.first?.url.absoluteString == "https://saga.gattey.com")

    let apiTitles = CreditItem.dataAndAPIs.map(\.name)
    #expect(apiTitles == ["Open Library", "Bookcover API", "Goodreads", "Contentful"])

    let libraryTitles = CreditItem.openSourceLibraries.map(\.name)
    #expect(
      libraryTitles == [
        "Contentful",
        "ContentfulPersistence",
        "Ifrit",
        "Sparkle",
        "ViewInspector",
        "InjectionNext",
      ]
    )
    for item in CreditItem.openSourceLibraries {
      #expect(item.version != nil)
      #expect(item.badge == "MIT")
      #expect(item.badgeURL != nil)
    }
  }

  @Test("AboutView and CreditsView render app identity, links, data sources, and libraries")
  @MainActor
  func aboutAndCreditsViewInspection() throws {
    let inspectedAbout = try AboutView().inspect()
    #expect(try inspectedAbout.find(text: "Saga").string() == "Saga")
    #expect(
      try inspectedAbout.find(text: "Crafted by Dylan Gattey").string()
        == "Crafted by Dylan Gattey")
    #expect(try inspectedAbout.find(text: "Website").string() == "Website")
    #expect(try inspectedAbout.find(text: "GitHub").string() == "GitHub")
    #expect(try inspectedAbout.find(text: "More by Dylan").string() == "More by Dylan")

    let inspectedCredits = try CreditsView().inspect()
    #expect(try inspectedCredits.find(text: "Data").string() == "Data")
    #expect(try inspectedCredits.find(text: "Open Source").string() == "Open Source")
    #expect(try inspectedCredits.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedCredits.find(text: "Bookcover API").string() == "Bookcover API")
    #expect(
      try inspectedCredits.find(text: "Fast fuzzy search for books and authors by Ukushu")
        .string() == "Fast fuzzy search for books and authors by Ukushu")
  }
}
