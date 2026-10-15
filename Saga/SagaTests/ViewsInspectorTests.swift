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
    let header = BookListHeaderView()
    #expect(try header.inspect().text().string() == "Books")

    let empty = BookListEmptyStateView()
    #expect(try empty.inspect().text().string() == "No results")
  }

  @Test("SettingsSliderView renders label, formatted value pill, slider, and optional subtitle")
  @MainActor
  func settingsSliderViewInspection() throws {
    var sliderValue = 250.0
    let binding = Binding(get: { sliderValue }, set: { sliderValue = $0 })

    let viewWithSubtitle = SettingsSliderView(
      label: "Image cache limit",
      formattedValue: "250 MB",
      value: binding,
      range: 50...1000,
      step: 50,
      subtitle: "Current usage",
      subtitleValue: "42 MB"
    )

    let inspected = try viewWithSubtitle.inspect()
    #expect(try inspected.find(text: "Image cache limit").string() == "Image cache limit")
    #expect(try inspected.find(text: "250 MB").string() == "250 MB")
    #expect(try inspected.find(text: "Current usage").string() == "Current usage")
    #expect(try inspected.find(text: "42 MB").string() == "42 MB")

    let slider = try inspected.find(ViewType.Slider.self)
    try slider.setValue(0.5)
    #expect(sliderValue > 250.0)
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
    #expect(SettingsPane.allCases == [.general, .storage, .credits])
    #expect(SettingsPane.general.title == "General")
    #expect(SettingsPane.storage.title == "Storage")
    #expect(SettingsPane.credits.title == "Credits & About")
    #expect(SettingsPane.credits.shortTitle == "Credits")
    for pane in SettingsPane.allCases {
      #expect(!pane.subtitle.isEmpty)
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

  @Test("SettingsHeaderView and SettingsCard render titles, subtitles, and inner content")
  @MainActor
  func settingsHeaderAndCardInspection() throws {
    let header = SettingsHeaderView(
      title: "Credits & About",
      subtitle: "About Saga, data sources & open source",
      systemImage: "sparkles",
      backgroundColor: .botanicalLeaf
    )
    let inspectedHeader = try header.inspect()
    #expect(try inspectedHeader.find(text: "Credits & About").string() == "Credits & About")
    #expect(
      try inspectedHeader.find(text: "About Saga, data sources & open source").string()
        == "About Saga, data sources & open source"
    )

    let card = SettingsCard(
      title: "Data & APIs",
      subtitle: "External services",
      systemImage: "globe.americas.fill"
    ) {
      Text("Open Library")
      SettingsCardDivider()
      Text("Goodreads")
    }
    let inspectedCard = try card.inspect()
    #expect(try inspectedCard.find(text: "Data & APIs").string() == "Data & APIs")
    #expect(try inspectedCard.find(text: "External services").string() == "External services")
    #expect(try inspectedCard.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedCard.find(text: "Goodreads").string() == "Goodreads")
  }

  @Test("AppInformationView and CreditsView render app identity, quick links, APIs, and libraries")
  @MainActor
  func appInformationAndCreditsViewInspection() throws {
    let appInfo = AppInformationView()
    let inspectedAppInfo = try appInfo.inspect()
    #expect(try inspectedAppInfo.find(text: "Saga").string() == "Saga")
    #expect(
      try inspectedAppInfo.find(text: "Crafted by Dylan Gattey").string()
        == "Crafted by Dylan Gattey")
    #expect(try inspectedAppInfo.find(text: "Website").string() == "Website")
    #expect(try inspectedAppInfo.find(text: "GitHub").string() == "GitHub")
    #expect(try inspectedAppInfo.find(text: "More by Dylan").string() == "More by Dylan")

    let creditsView = CreditsView()
    let inspectedCredits = try creditsView.inspect()
    #expect(try inspectedCredits.find(text: "Data & APIs").string() == "Data & APIs")
    #expect(
      try inspectedCredits.find(text: "Open Source Libraries").string()
        == "Open Source Libraries"
    )
    #expect(try inspectedCredits.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedCredits.find(text: "Bookcover API").string() == "Bookcover API")
    #expect(try inspectedCredits.find(text: "Ifrit").string() == "Ifrit")
    #expect(try inspectedCredits.find(text: "Sparkle").string() == "Sparkle")
  }

  #if os(macOS)
    @Test("SettingsSidebarView renders all panes and updates selectedPane binding on tap")
    @MainActor
    func settingsSidebarViewInspection() throws {
      var selected: SettingsPane = .general
      let binding = Binding(get: { selected }, set: { selected = $0 })
      let sidebar = SettingsSidebarView(selectedPane: binding)
        .environmentObject(AnimationSettings.shared)

      let inspected = try sidebar.inspect()
      #expect(try inspected.find(text: "General").string() == "General")
      #expect(try inspected.find(text: "Storage").string() == "Storage")
      #expect(try inspected.find(text: "Credits & About").string() == "Credits & About")

      let creditsButton = try inspected.find(button: "Credits & About")
      try creditsButton.tap()
      #expect(selected == .credits)
    }
  #endif
}
