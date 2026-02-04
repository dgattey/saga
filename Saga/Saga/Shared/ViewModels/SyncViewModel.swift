//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import Combine
import CoreData
import SwiftUI

/// Handles syncing data across the full app, delegating to service functions as needed
///
/// ## Two-Way Sync
/// This view model now supports bidirectional sync with Contentful:
/// - `sync()` - Pulls changes from Contentful (always available)
/// - `push()` - Pushes local changes to Contentful (requires management token)
/// - `fullSync()` - Performs both pull and push
///
/// Local CoreData changes are automatically detected and pushed if two-way sync is enabled.
/// The sync service handles conflict resolution using "latest-wins" based on timestamps.
final class SyncViewModel: ObservableObject {
  private var controller = PersistenceService()

  // MARK: - Published State

  @Published var isSyncing = false
  @Published var isPushing = false
  @Published var isResetting = false
  @Published var resetToken = UUID()

  /// Number of local changes waiting to be pushed to Contentful
  @Published var pendingPushCount = 0

  /// Whether two-way sync is available (management token configured)
  var isTwoWaySyncEnabled: Bool {
    controller.isTwoWaySyncEnabled
  }

  private var syncTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  var viewContext: NSManagedObjectContext {
    return controller.container.viewContext
  }

  /// Access to the two-way sync service for advanced usage
  var twoWaySyncService: TwoWaySyncService {
    controller.twoWaySyncService
  }

  init() {
    setupTwoWaySyncObservers()
  }

  // MARK: - Setup

  private func setupTwoWaySyncObservers() {
    // Observe push state from two-way sync service
    controller.twoWaySyncService.$isPushing
      .receive(on: DispatchQueue.main)
      .assign(to: &$isPushing)

    controller.twoWaySyncService.$pendingPushCount
      .receive(on: DispatchQueue.main)
      .assign(to: &$pendingPushCount)
  }

  // MARK: - Sync Operations

  /// Pulls changes from Contentful to CoreData
  /// This is the original one-way sync behavior
  func sync() async {
    LoggerService.log("Sync starting pull from Contentful", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isSyncing = true
      },
      finish: { [weak self] in
        self?.isSyncing = false
      },
      { [weak self] in
        try await self?.controller.syncWithApi()
      }
    )
  }

  /// Pushes local changes to Contentful (requires management token)
  /// Call this to manually trigger a push, or rely on automatic push
  func push() async {
    guard isTwoWaySyncEnabled else {
      LoggerService.log(
        "Two-way sync not enabled - add ContentfulManagementToken to config",
        level: .warning,
        surface: .sync
      )
      return
    }

    LoggerService.log("Sync starting push to Contentful", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isPushing = true
      },
      finish: { [weak self] in
        self?.isPushing = false
      },
      { [weak self] in
        try await self?.controller.pushToContentful()
      }
    )
  }

  /// Performs a full bidirectional sync: pull from Contentful, then push local changes
  func fullSync() async {
    LoggerService.log("Sync starting full bidirectional sync", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isSyncing = true
      },
      finish: { [weak self] in
        self?.isSyncing = false
      },
      { [weak self] in
        try await self?.controller.fullSync()
      }
    )
  }

  /// Resets all data, then syncs as long as there's no sync running already
  func resetAndSync() async {
    LoggerService.log("Sync starting reset + refresh", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isResetting = true
        self?.resetToken = UUID()
      },
      finish: { [weak self] in
        self?.isResetting = false
      },
      { [weak self] in
        try await self?.controller.resetAndSyncWithApi()
      }
    )
  }

  /// Helper to orchestrate some sync function, managing state as it does so
  private func orchestrateSync(
    start: @escaping () -> Void,
    finish: @escaping () -> Void,
    _ syncFunction: @escaping () async throws -> Void
  ) async {
    guard !isSyncing, !isResetting, !isPushing else { return }
    syncTask = Task(priority: .background) {
      await MainActor.run {
        start()
      }
      do {
        try await syncFunction()
        await MainActor.run {
          finish()
        }
      } catch {
        await MainActor.run {
          finish()
        }
        LoggerService.log("Sync failed", error: error, surface: .sync)
      }
    }
  }
}
