//
//  UpdaterViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import Foundation
import SwiftUI

#if os(macOS)
  import AppKit
  import Combine
  import Sparkle
#endif

// MARK: - Updater Configuration

/// Validated Sparkle configuration read from an `Info.plist` dictionary.
struct UpdaterConfiguration: Equatable, Sendable {
  let feedURLString: String
  let publicEDKey: String

  var feedURL: URL? {
    let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      let url = URL(string: trimmed),
      url.scheme?.lowercased() == "https",
      let host = url.host,
      !host.isEmpty
    else {
      return nil
    }
    return url
  }

  /// Ed25519 public keys encoded in base64 decode to 32 bytes.
  var hasValidPublicEDKey: Bool {
    let trimmed = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      let decoded = Data(base64Encoded: trimmed),
      decoded.count == 32
    else {
      return false
    }
    return true
  }

  var isReleaseConfigured: Bool {
    feedURL != nil && hasValidPublicEDKey
  }

  static func from(infoDictionary: [String: Any]?) -> UpdaterConfiguration {
    let feedURLString =
      (infoDictionary?[BundleKey.sparkleFeedURL.rawValue] as? String) ?? ""
    let publicEDKey =
      (infoDictionary?[BundleKey.sparklePublicEDKey.rawValue] as? String) ?? ""
    return UpdaterConfiguration(
      feedURLString: feedURLString,
      publicEDKey: publicEDKey
    )
  }

  static func fromMainBundle() -> UpdaterConfiguration {
    from(infoDictionary: Bundle.main.infoDictionary)
  }
}

// MARK: - Updater Mode

/// How the updater behaves for this launch.
enum UpdaterMode: Equatable, Sendable {
  /// Sparkle stays stopped: missing feed URL / EdDSA key, or running under unit tests.
  case inactive
  /// macOS App Translocation is running a quarantined copy of the app from a randomized read-only
  /// path, where Sparkle refuses to install updates. Checks explain how to clear quarantine instead.
  case translocated(quarantineFixCommand: String)
  case active

  static func resolve(
    configuration: UpdaterConfiguration,
    startUpdater: Bool,
    bundleURL: URL
  ) -> UpdaterMode {
    guard configuration.isReleaseConfigured, startUpdater else { return .inactive }
    // Matches Sparkle's own `SUHost` translocation check.
    guard bundleURL.path.contains("/AppTranslocation/") else { return .active }
    return .translocated(
      quarantineFixCommand:
        "xattr -dr com.apple.quarantine \"/Applications/\(bundleURL.lastPathComponent)\""
    )
  }
}

// MARK: - Update Session Lifecycle

/// Tracks whether Sparkle is actively presenting an update alert, downloading an update,
/// or installing an update so the app does not quit prematurely if windows close.
@MainActor
final class SparkleUpdateSession {
  static let shared = SparkleUpdateSession()

  private(set) var activeCount = 0

  var blocksQuitOnLastWindowClosed: Bool {
    activeCount > 0
  }

  func begin() {
    activeCount += 1
  }

  func end() {
    activeCount = max(0, activeCount - 1)
  }

  func reset() {
    activeCount = 0
  }
}

#if os(macOS)

  // MARK: - Sparkle Delegates

  /// Keeps `SparkleUpdateSession` active while Sparkle's standard UI is visible and
  /// brings the update alert to the foreground when a background launch check finds an update.
  final class SparkleStandardUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    @MainActor var onShowScheduledUpdateInForeground: (() -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool {
      true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
      _ update: SUAppcastItem,
      andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
      shouldHandleShowingScheduledUpdate(inImmediateFocus: immediateFocus)
    }

    func shouldHandleShowingScheduledUpdate(inImmediateFocus immediateFocus: Bool) -> Bool {
      // Return `false` for scheduled checks so `standardUserDriverWillHandleShowingUpdate` invokes
      // `checkForUpdates(nil)` (`showUpdateInFocus`) to activate the app and focus the alert.
      false
    }

    func standardUserDriverWillHandleShowingUpdate(
      _ handleShowingUpdate: Bool,
      forUpdate update: SUAppcastItem,
      state: SPUUserUpdateState
    ) {
      Task { @MainActor [weak self] in
        self?.handleShowingUpdateOnMainActor(handleShowingUpdate)
      }
    }

    @MainActor
    func handleShowingUpdateOnMainActor(_ handleShowingUpdate: Bool) {
      SparkleUpdateSession.shared.begin()
      NSApplication.shared.activate(ignoringOtherApps: true)
      if !handleShowingUpdate {
        onShowScheduledUpdateInForeground?()
      }
    }

    func standardUserDriverWillShowModalAlert() {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
    }

    func standardUserDriverWillFinishUpdateSession() {
      Task { @MainActor [weak self] in
        self?.finishUpdateSessionOnMainActor()
      }
    }

    @MainActor
    func finishUpdateSessionOnMainActor() {
      SparkleUpdateSession.shared.reset()
    }
  }

  /// Bridges `SPUUpdater` callbacks to `LoggerService`.
  final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
      Task { @MainActor in
        LoggerService.log(
          "Sparkle found valid update \(item.displayVersionString) (\(item.versionString))",
          level: .notice,
          surface: .updates
        )
      }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
      Task { @MainActor in
        SparkleUpdateSession.shared.reset()
        LoggerService.log(
          "Sparkle update cycle ended with error: \(error.localizedDescription)",
          level: .warning,
          surface: .updates
        )
      }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
      Task { @MainActor in
        SparkleUpdateSession.shared.begin()
        LoggerService.log(
          "Sparkle will install update \(item.displayVersionString) (\(item.versionString))",
          level: .notice,
          surface: .updates
        )
      }
    }
  }

  // MARK: - Updater View Model

  /// Wraps Sparkle's `SPUStandardUpdaterController` and exposes observable state for
  /// `MenuBarCommands` and `SettingsView`.
  @MainActor
  @Observable
  final class UpdaterViewModel {
    private(set) var canCheckForUpdates = false {
      didSet {
        guard canCheckForUpdates, isWaitingToCheckOnLaunch else { return }
        isWaitingToCheckOnLaunch = false
        checkForUpdatesOnLaunch()
      }
    }

    var automaticallyChecksForUpdates: Bool {
      didSet {
        guard shouldStartUpdater,
          controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates
        else { return }
        controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
      }
    }

    var automaticallyDownloadsUpdates: Bool {
      didSet {
        guard shouldStartUpdater,
          controller.updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates
        else { return }
        controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
      }
    }

    @ObservationIgnored let configuration: UpdaterConfiguration

    var isConfigured: Bool {
      configuration.isReleaseConfigured
    }

    @ObservationIgnored let mode: UpdaterMode
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let sparkleDelegate = SparkleUpdaterDelegate()
    @ObservationIgnored private let sparkleUserDriverDelegate = SparkleStandardUserDriverDelegate()
    @ObservationIgnored private var canCheckCancellable: AnyCancellable?
    @ObservationIgnored private var isWaitingToCheckOnLaunch = false
    @ObservationIgnored private(set) var didScheduleLaunchCheck = false
    @ObservationIgnored private(set) var didCheckOnLaunch = false

    private var shouldStartUpdater: Bool {
      mode == .active
    }

    init(
      configuration: UpdaterConfiguration = .fromMainBundle(),
      startUpdater: Bool = !PersistenceService.isRunningUnitTests,
      bundleURL: URL = Bundle.main.bundleURL
    ) {
      self.configuration = configuration
      let mode = UpdaterMode.resolve(
        configuration: configuration,
        startUpdater: startUpdater,
        bundleURL: bundleURL
      )
      self.mode = mode
      let shouldStart = mode == .active

      let controller = SPUStandardUpdaterController(
        startingUpdater: shouldStart,
        updaterDelegate: sparkleDelegate,
        userDriverDelegate: sparkleUserDriverDelegate
      )
      self.controller = controller
      self.automaticallyChecksForUpdates =
        shouldStart ? controller.updater.automaticallyChecksForUpdates : true
      self.automaticallyDownloadsUpdates =
        shouldStart ? controller.updater.automaticallyDownloadsUpdates : false

      sparkleUserDriverDelegate.onShowScheduledUpdateInForeground = { [weak self] in
        self?.controller.checkForUpdates(nil)
      }

      switch mode {
      case .active:
        canCheckCancellable = controller.updater.publisher(for: \.canCheckForUpdates)
          .receive(on: RunLoop.main)
          .sink { [weak self] canCheck in
            self?.canCheckForUpdates = canCheck
          }

        // Trigger a background update check shortly after launch if automatic checks are enabled
        // so newly published releases are detected immediately on app startup.
        Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(1))
          self?.checkForUpdatesOnLaunch()
        }
      case .translocated:
        // Sparkle stays stopped so its scheduled checks never reach its dead-end
        // "running from the location it was downloaded to" alert; checks show guidance instead.
        canCheckForUpdates = true
        LoggerService.log(
          "Sparkle disabled: app is translocated at \(bundleURL.path)",
          level: .warning,
          surface: .updates
        )
      case .inactive:
        if !configuration.isReleaseConfigured {
          LoggerService.log(
            "Sparkle disabled for this build (missing or invalid SUFeedURL / SUPublicEDKey)",
            level: .debug,
            surface: .updates
          )
        }
      }
    }

    /// Schedules a one-time background update check once the main window has appeared and Sparkle is ready.
    func mainWindowDidAppear() {
      guard !didScheduleLaunchCheck else { return }
      didScheduleLaunchCheck = true
      guard isConfigured, automaticallyChecksForUpdates else { return }

      if canCheckForUpdates {
        checkForUpdatesOnLaunch()
        return
      }

      isWaitingToCheckOnLaunch = true
    }

    /// Runs `checkForUpdatesInBackground()` once per launch when automatic update checks are enabled,
    /// presenting Sparkle's standard update dialog if a newer version is available.
    func checkForUpdatesOnLaunch() {
      guard isConfigured, automaticallyChecksForUpdates, !didCheckOnLaunch else { return }
      didCheckOnLaunch = true
      switch mode {
      case .inactive:
        return
      case .translocated(let quarantineFixCommand):
        presentTranslocationAlert(quarantineFixCommand: quarantineFixCommand)
      case .active:
        guard !controller.updater.sessionInProgress else { return }
        LoggerService.log(
          "Checking for updates in background on launch",
          level: .notice,
          surface: .updates
        )
        controller.updater.checkForUpdatesInBackground()
      }
    }

    /// Triggers an interactive update check from the menu bar or Settings window.
    func checkForUpdates() {
      switch mode {
      case .inactive:
        return
      case .translocated(let quarantineFixCommand):
        presentTranslocationAlert(quarantineFixCommand: quarantineFixCommand)
      case .active:
        controller.checkForUpdates(nil)
      }
    }

    // MARK: - Translocation Guidance

    private func presentTranslocationAlert(quarantineFixCommand: String) {
      // Deferred so the modal never runs inside a SwiftUI view update (`onAppear`).
      Task { @MainActor in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Saga can’t install updates from this copy"
        alert.informativeText = """
          macOS is running Saga from a temporary, read-only location because the app is still \
          marked as downloaded from the internet. Quit Saga, run this command in Terminal, then \
          reopen Saga from your Applications folder:

          \(quarantineFixCommand)

          If Saga isn’t in your Applications folder yet, drag it there in Finder first.
          """
        alert.addButton(withTitle: "Copy Command and Quit")
        alert.addButton(withTitle: "Not Now")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(quarantineFixCommand, forType: .string)
        NSApplication.shared.terminate(nil)
      }
    }
  }

  // MARK: - Menu Item View

  /// Menu bar button placed under the app menu ("Saga" -> "Check for Updates…").
  struct CheckForUpdatesMenuItem: View {
    var updaterViewModel: UpdaterViewModel

    var body: some View {
      Button("Check for Updates…") {
        updaterViewModel.checkForUpdates()
      }
      .disabled(!updaterViewModel.canCheckForUpdates)
    }
  }
#endif
