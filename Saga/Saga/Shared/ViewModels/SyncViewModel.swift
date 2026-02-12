//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import Combine
import CoreData
import SwiftUI

/// Handles two-way sync with Contentful.
///
/// Sync is bidirectional:
/// - Pull: Fetches changes from Contentful (delta sync via tokens)
/// - Push: Sends dirty local changes to Contentful (via CMA)
///
/// Local CoreData changes automatically set `isDirty = true` and trigger sync.
/// Conflicts are resolved using "latest-wins" based on `updatedAt` timestamps.
///
/// ## Preview Mode
/// When `usePreviewContent` is toggled in Settings, the view model recreates
/// `PersistenceService` with the new mode and performs a fresh sync.
final class SyncViewModel: ObservableObject {
  private var controller: PersistenceService
  private var cancellables = Set<AnyCancellable>()
  private var syncTask: Task<Void, Never>?

  // MARK: - Published State

  @Published var isSyncing = false
  @Published var isResetting = false
  @Published var resetToken = UUID()
  @Published var pendingPushCount = 0

  var viewContext: NSManagedObjectContext {
    controller.container.viewContext
  }

  init() {
    let usePreview = UserDefaults.standard.bool(forKey: SettingsView.usePreviewContentKey)
    controller = PersistenceService(usePreviewContent: usePreview)
    setupObservers()
    observePreviewModeChanges()

    // Initial sync on launch
    Task { [weak self] in
      await self?.sync()
    }
  }

  private func setupObservers() {
    controller.twoWaySyncService.$isSyncing
      .receive(on: DispatchQueue.main)
      .assign(to: &$isSyncing)

    controller.twoWaySyncService.$pendingPushCount
      .receive(on: DispatchQueue.main)
      .assign(to: &$pendingPushCount)
  }

  private func observePreviewModeChanges() {
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .compactMap { _ in
        UserDefaults.standard.bool(forKey: SettingsView.usePreviewContentKey)
      }
      .removeDuplicates()
      .dropFirst()  // Skip initial value (already handled in init)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] usePreview in
        self?.switchToPreviewMode(usePreview)
      }
      .store(in: &cancellables)
  }

  private func switchToPreviewMode(_ usePreview: Bool) {
    guard controller.usePreviewContent != usePreview else { return }

    LoggerService.log(
      "Switching to \(usePreview ? "preview" : "delivery") mode — resetting data",
      level: .notice,
      surface: .sync
    )

    // Cancel any in-flight sync
    syncTask?.cancel()
    syncTask = nil

    // Recreate controller with new mode
    controller = PersistenceService(usePreviewContent: usePreview)
    setupObservers()

    // Reset and sync: wipe local data since preview/delivery content differs
    Task {
      await resetAndSync()
    }
  }

  // MARK: - Sync Operations

  /// Performs a full bidirectional sync: pull from Contentful, then push dirty local changes
  func sync() async {
    LoggerService.log("Starting sync", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in self?.isSyncing = true },
      finish: { [weak self] in self?.isSyncing = false },
      { [weak self] in try await self?.controller.sync() }
    )
  }

  /// Resets all local data and resyncs from Contentful
  func resetAndSync() async {
    LoggerService.log("Starting reset + sync", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isResetting = true
        self?.resetToken = UUID()
      },
      finish: { [weak self] in self?.isResetting = false },
      { [weak self] in try await self?.controller.resetAndSync() }
    )
  }

  private func orchestrateSync(
    start: @escaping () -> Void,
    finish: @escaping () -> Void,
    _ syncFunction: @escaping () async throws -> Void
  ) async {
    guard !isSyncing, !isResetting else { return }
    syncTask = Task(priority: .background) {
      await MainActor.run { start() }
      do {
        try await syncFunction()
        await MainActor.run { finish() }
      } catch {
        await MainActor.run { finish() }
        LoggerService.log("Sync failed", error: error, surface: .sync)
      }
    }
  }
}
