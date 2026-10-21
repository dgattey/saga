//
//  UpdaterTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

import Foundation
import SwiftUI
import Testing
import ViewInspector

@testable import Saga

@Suite("Sparkle Updater Configuration, Session & ViewModel")
struct UpdaterTests {
  private static let validFeedURL =
    "https://github.com/dgattey/saga/releases/latest/download/appcast.xml"
  private static let validEDKey = "p7SwMco+T0cqVfWgj0I99JtCoRX8a/NeM72wkLTvODM="

  @Test("UpdaterConfiguration validates HTTPS feed URL and 32-byte Ed25519 public key")
  func updaterConfigurationValidation() {
    let valid = UpdaterConfiguration(
      feedURLString: Self.validFeedURL,
      publicEDKey: Self.validEDKey
    )
    #expect(valid.feedURL?.absoluteString == Self.validFeedURL)
    #expect(valid.hasValidPublicEDKey)
    #expect(valid.isReleaseConfigured)

    let httpFeed = UpdaterConfiguration(
      feedURLString: "http://github.com/dgattey/saga/releases/latest/download/appcast.xml",
      publicEDKey: Self.validEDKey
    )
    #expect(httpFeed.feedURL == nil)
    #expect(!httpFeed.isReleaseConfigured)

    let emptyFeed = UpdaterConfiguration(
      feedURLString: "   ",
      publicEDKey: Self.validEDKey
    )
    #expect(emptyFeed.feedURL == nil)
    #expect(!emptyFeed.isReleaseConfigured)

    let shortKey = UpdaterConfiguration(
      feedURLString: Self.validFeedURL,
      publicEDKey: Data("short".utf8).base64EncodedString()
    )
    #expect(!shortKey.hasValidPublicEDKey)
    #expect(!shortKey.isReleaseConfigured)

    let malformedKey = UpdaterConfiguration(
      feedURLString: Self.validFeedURL,
      publicEDKey: "not-valid-base64!!!"
    )
    #expect(!malformedKey.hasValidPublicEDKey)
    #expect(!malformedKey.isReleaseConfigured)
  }

  @Test("UpdaterConfiguration reads SUFeedURL and SUPublicEDKey from an Info.plist dictionary")
  func updaterConfigurationFromInfoDictionary() {
    let dict: [String: Any] = [
      BundleKey.sparkleFeedURL.rawValue: Self.validFeedURL,
      BundleKey.sparklePublicEDKey.rawValue: Self.validEDKey,
    ]
    let parsed = UpdaterConfiguration.from(infoDictionary: dict)
    #expect(parsed.isReleaseConfigured)
    #expect(parsed.feedURLString == Self.validFeedURL)
    #expect(parsed.publicEDKey == Self.validEDKey)

    let emptyParsed = UpdaterConfiguration.from(infoDictionary: nil)
    #expect(!emptyParsed.isReleaseConfigured)
  }

  @Test("SparkleUpdateSession tracks nested update sessions and resets cleanly")
  @MainActor
  func sparkleUpdateSessionLifecycle() {
    let session = SparkleUpdateSession()
    #expect(session.activeCount == 0)
    #expect(!session.blocksQuitOnLastWindowClosed)

    session.begin()
    #expect(session.activeCount == 1)
    #expect(session.blocksQuitOnLastWindowClosed)

    session.begin()
    #expect(session.activeCount == 2)

    session.end()
    #expect(session.activeCount == 1)
    #expect(session.blocksQuitOnLastWindowClosed)

    session.end()
    #expect(session.activeCount == 0)
    #expect(!session.blocksQuitOnLastWindowClosed)

    // Extra end() calls never drop below zero
    session.end()
    #expect(session.activeCount == 0)

    session.begin()
    session.begin()
    session.reset()
    #expect(session.activeCount == 0)
    #expect(!session.blocksQuitOnLastWindowClosed)
  }

  #if os(macOS)
    @Test("UpdaterViewModel initializes inertly in unit tests and schedules launch check once")
    @MainActor
    func updaterViewModelLifecycle() {
      let configured = UpdaterConfiguration(
        feedURLString: Self.validFeedURL,
        publicEDKey: Self.validEDKey
      )
      let viewModel = UpdaterViewModel(configuration: configured, startUpdater: false)
      #expect(viewModel.isConfigured)
      #expect(!viewModel.canCheckForUpdates)
      #expect(viewModel.automaticallyChecksForUpdates)
      #expect(!viewModel.automaticallyDownloadsUpdates)
      #expect(!viewModel.didScheduleLaunchCheck)
      #expect(!viewModel.didCheckOnLaunch)

      viewModel.mainWindowDidAppear()
      #expect(viewModel.didScheduleLaunchCheck)
      // Repeating mainWindowDidAppear is a no-op
      viewModel.mainWindowDidAppear()
      #expect(viewModel.didScheduleLaunchCheck)

      viewModel.checkForUpdatesOnLaunch()
      #expect(viewModel.didCheckOnLaunch)

      // Toggling preferences in inert test mode updates published state without crashing
      viewModel.automaticallyChecksForUpdates = false
      #expect(!viewModel.automaticallyChecksForUpdates)
      viewModel.automaticallyDownloadsUpdates = true
      #expect(viewModel.automaticallyDownloadsUpdates)
      viewModel.checkForUpdates()

      // When automatic checks are disabled, checkForUpdatesOnLaunch is skipped
      let disabledAutoViewModel = UpdaterViewModel(configuration: configured, startUpdater: false)
      disabledAutoViewModel.automaticallyChecksForUpdates = false
      disabledAutoViewModel.mainWindowDidAppear()
      disabledAutoViewModel.checkForUpdatesOnLaunch()
      #expect(!disabledAutoViewModel.didCheckOnLaunch)

      let unconfigured = UpdaterViewModel(
        configuration: UpdaterConfiguration(feedURLString: "", publicEDKey: ""),
        startUpdater: false
      )
      #expect(!unconfigured.isConfigured)
      unconfigured.mainWindowDidAppear()
      #expect(unconfigured.didScheduleLaunchCheck)
      #expect(!unconfigured.didCheckOnLaunch)
    }

    @Test(
      "SparkleStandardUserDriverDelegate routes scheduled updates to foreground and manages session"
    )
    @MainActor
    func sparkleStandardUserDriverDelegateForegroundBehavior() {
      SparkleUpdateSession.shared.reset()
      let delegate = SparkleStandardUserDriverDelegate()
      var foregroundPresentationCount = 0
      delegate.onShowScheduledUpdateInForeground = {
        foregroundPresentationCount += 1
      }

      #expect(delegate.supportsGentleScheduledUpdateReminders)
      #expect(!delegate.shouldHandleShowingScheduledUpdate(inImmediateFocus: true))
      #expect(!delegate.shouldHandleShowingScheduledUpdate(inImmediateFocus: false))

      delegate.handleShowingUpdateOnMainActor(false)
      #expect(SparkleUpdateSession.shared.activeCount == 1)
      #expect(foregroundPresentationCount == 1)

      delegate.handleShowingUpdateOnMainActor(true)
      #expect(SparkleUpdateSession.shared.activeCount == 2)
      #expect(foregroundPresentationCount == 1)

      delegate.standardUserDriverWillShowModalAlert()
      delegate.finishUpdateSessionOnMainActor()
      #expect(SparkleUpdateSession.shared.activeCount == 0)
    }

    @Test(
      "CheckForUpdatesMenuItem renders Check for Updates… button disabled when canCheckForUpdates is false"
    )
    @MainActor
    func checkForUpdatesMenuItemInspection() throws {
      let viewModel = UpdaterViewModel(
        configuration: UpdaterConfiguration(
          feedURLString: Self.validFeedURL,
          publicEDKey: Self.validEDKey
        ),
        startUpdater: false
      )
      let menuItem = CheckForUpdatesMenuItem(updaterViewModel: viewModel)
      let button = try menuItem.inspect().button()
      #expect(try button.labelView().text().string() == "Check for Updates…")
      #expect(button.isDisabled())
    }
  #endif
}
