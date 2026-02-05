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
final class SyncViewModel: ObservableObject {
  private var controller = PersistenceService()
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
    setupObservers()
  }

  private func setupObservers() {
    controller.twoWaySyncService.$isSyncing
      .receive(on: DispatchQueue.main)
      .assign(to: &$isSyncing)

    controller.twoWaySyncService.$pendingPushCount
      .receive(on: DispatchQueue.main)
      .assign(to: &$pendingPushCount)
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
