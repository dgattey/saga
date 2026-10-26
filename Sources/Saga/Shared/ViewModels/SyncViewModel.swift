//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import CoreData
import SwiftUI

@MainActor
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
      { [controller] in
        _ = await GoodreadsSyncService.triggerIfConfigured()
        try await controller.syncWithApi()
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
      { [controller] in
        _ = await GoodreadsSyncService.triggerIfConfigured()
        try await controller.syncWithApi(reset: true)
      }
    )
  }

  // MARK: - Private Methods

  /// Helper to start/finish some sync action with a given function
  private func orchestrateSync(
    cancelExisting: Bool = false,
    start: @escaping () -> Void,
    finish: @escaping () -> Void,
    _ syncFunction: @escaping @Sendable () async throws -> Void
  ) async {
    if cancelExisting, isSyncing, let existing = syncTask {
      existing.cancel()
      await existing.value
    }
    guard !isSyncing, !isResetting else { return }
    start()

    let task = Task(priority: .utility) {
      do {
        try await syncFunction()
        finish()
      } catch {
        finish()
        LoggerService.log("Sync failed", error: error, surface: .sync)
      }
    }
    syncTask = task
    await task.value
  }
}
