//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import CoreData
import SwiftUI

@Observable
final class SyncViewModel {
  @ObservationIgnored let controller: PersistenceService
  var isSyncing = false
  var isResetting = false
  var resetToken = UUID()
  @ObservationIgnored private var syncTask: Task<Void, Never>?

  init(controller: PersistenceService = PersistenceService()) {
    self.controller = controller
  }

  var viewContext: NSManagedObjectContext {
    controller.container.viewContext
  }

  // MARK: - Sync Operations

  /// Triggers the remote Goodreads → Contentful sync endpoint (when configured) and then
  /// pulls the latest published Contentful entries into Core Data.
  func sync() async {
    LoggerService.log("Sync starting refresh", level: .notice, surface: .sync)
    await orchestrateSync(
      start: { [weak self] in
        self?.isSyncing = true
      },
      finish: { [weak self] in
        self?.isSyncing = false
      },
      { [weak self] in
        guard let self else { return }
        _ = await GoodreadsSyncService.triggerIfConfigured()
        try await self.controller.syncWithApi()
      }
    )
  }

  /// Resets all data in the store and then triggers a sync, unless one is already running
  func resetAndSync() async {
    LoggerService.log("Sync starting reset", level: .notice, surface: .sync)
    await orchestrateSync(
      cancelExisting: true,
      start: { [weak self] in
        self?.isSyncing = false
        self?.isResetting = true
      },
      finish: { [weak self] in
        self?.resetToken = UUID()
        self?.isResetting = false
      },
      { [weak self] in
        guard let self else { return }
        _ = await GoodreadsSyncService.triggerIfConfigured()
        try await self.controller.syncWithApi(reset: true)
      }
    )
  }

  // MARK: - Private Methods

  /// Helper to start/finish some sync action with a given function
  private func orchestrateSync(
    cancelExisting: Bool = false,
    start: @escaping () -> Void,
    finish: @escaping () -> Void,
    _ syncFunction: @escaping () async throws -> Void
  ) async {
    if cancelExisting, let existing = await MainActor.run(body: { isSyncing ? syncTask : nil }) {
      existing.cancel()
      await existing.value
    }
    let shouldStart = await MainActor.run {
      guard !isSyncing, !isResetting else { return false }
      start()
      return true
    }
    guard shouldStart else { return }

    let task = Task(priority: .utility) {
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
    syncTask = task
    await task.value
  }
}
