//
//  SettingsViewTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI
import Testing
import ViewInspector

@testable import Saga

@Suite("SettingsView & Settings Models")
struct SettingsViewTests {
  @Test("SettingsPane exposes expected metadata and badge view for all settings categories")
  @MainActor
  func settingsPaneMetadataInspection() throws {
    #expect(SettingsPane.allCases == [.storage, .interface, .about])
    #expect(SettingsPane.allCases.map(\.title) == ["Data & Storage", "Interface", "About"])
    for pane in SettingsPane.allCases {
      #expect(!pane.systemImage.isEmpty)
      #expect(pane.id == pane.rawValue)
      let badge = try SettingsPaneBadge(pane: pane).inspect()
      #expect(try badge.find(ViewType.Image.self).actualImage().name() == pane.systemImage)
    }
  }

  @Test("SettingsView formats cache limits and byte counts")
  func cacheLimitFormatting() {
    #expect(SettingsView.formatLimit(0) == "Unlimited")
    #expect(SettingsView.formatLimit(0.5) == "500 MB")
    #expect(SettingsView.formatLimit(5) == "5 GB")
    #expect(SettingsView.cacheLimitOptions.contains(5))
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
      ]
    )
    for item in CreditItem.openSourceLibraries {
      #expect(item.version != nil)
      #expect(item.badge == "MIT")
      #expect(item.badgeURL != nil)
    }
  }

  @Test("SettingsView renders grouped forms for Data & Storage, Interface, About, and Credits")
  @MainActor
  func settingsPaneFormsInspection() throws {
    let settingsView = SettingsView()

    let inspectedStorage = try settingsView.paneForm(for: .storage).inspect()
    #expect(try inspectedStorage.find(text: "Library Sync").string() == "Library Sync")
    #expect(
      try inspectedStorage.find(text: "Contentful & Goodreads").string() == "Contentful & Goodreads"
    )
    #expect(try inspectedStorage.find(text: "Sync Now").string() == "Sync Now")
    #expect(
      try inspectedStorage.find(text: "Reset local library").string() == "Reset local library"
    )
    #expect(try inspectedStorage.find(text: "Reset & Re-sync").string() == "Reset & Re-sync")
    #expect(try inspectedStorage.find(text: "Local Caches").string() == "Local Caches")
    #expect(try inspectedStorage.find(text: "Image cache").string() == "Image cache")
    #expect(try inspectedStorage.find(text: "Network cache").string() == "Network cache")
    #expect(try inspectedStorage.find(text: "Clear Caches").string() == "Clear Caches")

    let inspectedInterface = try settingsView.paneForm(for: .interface).inspect()
    #expect(
      try inspectedInterface.find(text: "Motion & Animations").string() == "Motion & Animations"
    )
    #expect(try inspectedInterface.find(text: "Spring response").string() == "Spring response")
    #expect(try inspectedInterface.find(text: "Spring damping").string() == "Spring damping")
    #expect(try inspectedInterface.find(text: "Reset to Defaults").string() == "Reset to Defaults")

    let inspectedAbout = try settingsView.paneForm(for: .about).inspect()
    #expect(try inspectedAbout.find(text: "Saga").string() == "Saga")
    #expect(try inspectedAbout.find(text: "Dylan Gattey").string() == "Dylan Gattey")
    #expect(try inspectedAbout.find(text: "Website").string() == "Website")
    #expect(try inspectedAbout.find(text: "GitHub").string() == "GitHub")
    #expect(try inspectedAbout.find(text: "More by Dylan").string() == "More by Dylan")
    #expect(try inspectedAbout.find(text: "Services & Data").string() == "Services & Data")
    #expect(try inspectedAbout.find(text: "Open Source").string() == "Open Source")
    #expect(try inspectedAbout.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedAbout.find(text: "Bookcover API").string() == "Bookcover API")
    #expect(
      try inspectedAbout.find(text: "Fast fuzzy search for books and authors by Ukushu")
        .string() == "Fast fuzzy search for books and authors by Ukushu")

    let inspectedCredits = try settingsView.creditsForm.inspect()
    #expect(try inspectedCredits.find(text: "Services & Data").string() == "Services & Data")
    #expect(try inspectedCredits.find(text: "Open Source").string() == "Open Source")
  }
}
