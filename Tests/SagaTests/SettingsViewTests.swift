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
  @Test("SettingsPane and SettingsPaneSection expose metadata, badges, and headers for all 6 panes")
  @MainActor
  func settingsPaneMetadataInspection() throws {
    #expect(
      SettingsPane.allCases == [
        .general,
        .sync,
        .storage,
        .animations,
        .credits,
        .about,
      ]
    )
    #expect(
      SettingsPane.allCases.map(\.title) == [
        "General",
        "Sync",
        "Storage",
        "Animations",
        "Credits",
        "About",
      ]
    )
    #expect(
      SettingsPaneSection.allCases.flatMap(\.panes) == SettingsPane.allCases
    )
    #expect(SettingsPaneSection.general.title == nil)
    #expect(SettingsPaneSection.library.title == "Library")
    #expect(SettingsPaneSection.interface.title == "Interface")
    #expect(SettingsPaneSection.app.title == "App")

    for pane in SettingsPane.allCases {
      #expect(!pane.systemImage.isEmpty)
      #expect(pane.id == pane.rawValue)

      let badge = try SettingsPaneBadge(pane: pane).inspect()
      #expect(try badge.find(ViewType.Image.self).actualImage().name() == pane.systemImage)

      let header = try SettingsHeaderView(pane: pane).inspect()
      #expect(try header.find(text: pane.title).string() == pane.title)
      #expect(try header.find(ViewType.Image.self).actualImage().name() == pane.systemImage)
    }
  }

  @Test("CacheLimitRow formats cache limits and byte counts")
  @MainActor
  func cacheLimitFormatting() throws {
    #expect(CacheLimitRow.formatLimit(0) == "Unlimited")
    #expect(CacheLimitRow.formatLimit(0.5) == "500 MB")
    #expect(CacheLimitRow.formatLimit(5) == "5 GB")
    #expect(CacheLimitRow.limitOptions == [0.1, 0.5, 1, 5, 10, 0])

    var limit: Double = 5
    let row = CacheLimitRow(
      title: "Image cache",
      limitGB: Binding(get: { limit }, set: { limit = $0 }),
      currentSizeBytes: 0,
      onLimitChange: {}
    )
    let inspectedRow = try row.inspect()
    #expect(try inspectedRow.find(text: "Image cache").string() == "Image cache")
    #expect(try inspectedRow.find(text: "5 GB").string() == "5 GB")
  }

  @Test("CreditItem, QuickLinkItem, CreditRowView, and AppInformationView render expected content")
  @MainActor
  func creditAndAppInformationInspection() throws {
    let quickLinkTitles = QuickLinkItem.all.map(\.title)
    #expect(quickLinkTitles == ["Website", "GitHub", "More by Dylan"])
    #expect(QuickLinkItem.all.first?.url.absoluteString == "https://saga.gattey.com")

    let apiTitles = CreditItem.dataAndAPIs.map(\.name)
    #expect(apiTitles == ["Open Library", "Bookcover API", "Goodreads", "Contentful"])

    let libraryTitles = CreditItem.openSourceLibraries.map(\.name)
    #expect(
      libraryTitles == [
        "Contentful",
        "Ifrit",
        "Sparkle",
        "ViewInspector",
      ]
    )
    for item in CreditItem.openSourceLibraries {
      #expect(item.version != nil)
      #expect(item.badge == "MIT")
      #expect(item.badgeURL != nil)
      let row = try CreditRowView(item: item).inspect()
      #expect(try row.find(text: item.name).string() == item.name)
      #expect(try row.find(text: item.subtitle).string() == item.subtitle)
      #expect(try row.find(text: item.badge).string() == item.badge)
    }

    let appInfo = try AppInformationView().inspect()
    #expect(try appInfo.find(text: "Saga").string() == "Saga")
    #expect(
      try appInfo.find(text: "Personal library & reading tracker for macOS and iOS").string()
        == "Personal library & reading tracker for macOS and iOS"
    )
    #expect(try appInfo.find(text: "Crafted by Dylan Gattey").string() == "Crafted by Dylan Gattey")
    #expect(try appInfo.find(text: "Website").string() == "Website")
    #expect(try appInfo.find(text: "GitHub").string() == "GitHub")
    #expect(try appInfo.find(text: "More by Dylan").string() == "More by Dylan")
  }

  @Test("SettingsView renders grouped forms for all 6 panes and Credits")
  @MainActor
  func settingsPaneFormsInspection() throws {
    let settingsView = SettingsView()

    let inspectedGeneral = try settingsView.paneForm(for: .general).inspect()
    #expect(
      try inspectedGeneral.find(text: "Software Updates").string() == "Software Updates"
    )
    #expect(
      try inspectedGeneral.find(text: "Automatically check for updates").string()
        == "Automatically check for updates"
    )
    #expect(
      try inspectedGeneral.find(text: "Automatically download updates").string()
        == "Automatically download updates"
    )
    #expect(
      try inspectedGeneral.find(text: "Check for Updates…").string() == "Check for Updates…"
    )

    let inspectedSync = try settingsView.paneForm(for: .sync).inspect()
    #expect(try inspectedSync.find(text: "Library Sync").string() == "Library Sync")
    #expect(
      try inspectedSync.find(text: "Contentful & Goodreads").string() == "Contentful & Goodreads"
    )
    #expect(try inspectedSync.find(text: "Sync Now").string() == "Sync Now")
    #expect(
      try inspectedSync.find(text: "Reset local library").string() == "Reset local library"
    )
    #expect(try inspectedSync.find(text: "Reset & Re-sync").string() == "Reset & Re-sync")

    let inspectedStorage = try settingsView.paneForm(for: .storage).inspect()
    #expect(try inspectedStorage.find(text: "Cache Limits").string() == "Cache Limits")
    #expect(try inspectedStorage.find(text: "Image cache").string() == "Image cache")
    #expect(try inspectedStorage.find(text: "Network cache").string() == "Network cache")
    #expect(try inspectedStorage.find(text: "Maintenance").string() == "Maintenance")
    #expect(
      try inspectedStorage.find(text: "Cached covers & responses").string()
        == "Cached covers & responses"
    )
    #expect(try inspectedStorage.find(text: "Clear Caches").string() == "Clear Caches")

    let inspectedAnimations = try settingsView.paneForm(for: .animations).inspect()
    #expect(
      try inspectedAnimations.find(text: "Motion & Animations").string() == "Motion & Animations"
    )
    #expect(try inspectedAnimations.find(text: "Spring response").string() == "Spring response")
    #expect(try inspectedAnimations.find(text: "Spring damping").string() == "Spring damping")
    #expect(try inspectedAnimations.find(text: "Reset to Defaults").string() == "Reset to Defaults")

    let inspectedCredits = try settingsView.paneForm(for: .credits).inspect()
    #expect(try inspectedCredits.find(text: "Data & Services").string() == "Data & Services")
    #expect(try inspectedCredits.find(text: "Open Source").string() == "Open Source")
    #expect(try inspectedCredits.find(text: "Open Library").string() == "Open Library")
    #expect(try inspectedCredits.find(text: "Bookcover API").string() == "Bookcover API")
    #expect(
      try inspectedCredits.find(text: "Fast fuzzy search for books and authors by Ukushu")
        .string() == "Fast fuzzy search for books and authors by Ukushu"
    )

    let inspectedAbout = try settingsView.paneForm(for: .about).inspect()
    #expect(try inspectedAbout.find(text: "Saga").string() == "Saga")
    #expect(
      try inspectedAbout.find(text: "Crafted by Dylan Gattey").string() == "Crafted by Dylan Gattey"
    )
    #expect(try inspectedAbout.find(text: "Website").string() == "Website")
    #expect(try inspectedAbout.find(text: "GitHub").string() == "GitHub")
    #expect(try inspectedAbout.find(text: "More by Dylan").string() == "More by Dylan")

    let inspectedCreditsSheet = try settingsView.creditsForm.inspect()
    #expect(try inspectedCreditsSheet.find(text: "Data & Services").string() == "Data & Services")
    #expect(try inspectedCreditsSheet.find(text: "Open Source").string() == "Open Source")
  }
}
