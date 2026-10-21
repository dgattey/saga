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
    #expect(SettingsPane.allCases == [.general, .storage, .credits, .about])
    #expect(SettingsPane.allCases.map(\.title) == ["General", "Storage", "Credits", "About"])
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
        "InjectionNext",
      ]
    )
    for item in CreditItem.openSourceLibraries {
      #expect(item.version != nil)
      #expect(item.badge == "MIT")
      #expect(item.badgeURL != nil)
    }
  }

  @Test("SettingsView renders grouped forms for Credits and About panes")
  @MainActor
  func settingsPaneFormsInspection() throws {
    let settingsView = SettingsView()
    let inspectedAbout = try settingsView.paneForm(for: .about).inspect()
    #expect(try inspectedAbout.find(text: "Saga").string() == "Saga")
    #expect(try inspectedAbout.find(text: "Dylan Gattey").string() == "Dylan Gattey")
    #expect(try inspectedAbout.find(text: "Website").string() == "Website")
    #expect(try inspectedAbout.find(text: "GitHub").string() == "GitHub")
    #expect(try inspectedAbout.find(text: "More by Dylan").string() == "More by Dylan")

    let inspectedCredits = try settingsView.paneForm(for: .credits).inspect()
    #expect(try inspectedCredits.find(text: "Data").string() == "Data")
    #expect(try inspectedCredits.find(text: "Open Source").string() == "Open Source")
    #expect(try inspectedCredits.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedCredits.find(text: "Bookcover API").string() == "Bookcover API")
    #expect(
      try inspectedCredits.find(text: "Fast fuzzy search for books and authors by Ukushu")
        .string() == "Fast fuzzy search for books and authors by Ukushu")
  }
}
