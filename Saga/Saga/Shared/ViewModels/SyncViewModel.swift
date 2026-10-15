//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import Combine
import CoreData
import SwiftUI

final class SyncViewModel: ObservableObject {
  let controller = PersistenceService()
  @Published var isSyncing = false
  @Published var isResetting = false
  @Published var resetToken = UUID()
  private var syncTask: Task<Void, Never>?

  var viewContext: NSManagedObjectContext {
    controller.container.viewContext
  }

  // MARK: - Sync Operations

  /// Syncs with Goodreads (if configured) and Contentful if there's no sync running already.
  func sync() async {
    await syncWithContentful()
  }

  /// Triggers the remote Goodreads → Contentful sync endpoint (when configured) and then
  /// pulls the latest published Contentful entries into Core Data.
  func syncWithContentful() async {
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
      start: { [weak self] in
        self?.isResetting = true
      },
      finish: { [weak self] in
        self?.resetToken = UUID()
        self?.isResetting = false
      },
      { [weak self] in
        guard let self else { return }
        _ = await GoodreadsSyncService.triggerIfConfigured()
        try await self.controller.resetAndSyncWithApi()
      }
    )
  }

  // MARK: - Private Methods

  /// Helper to start/finish some sync action with a given function
  private func orchestrateSync(
    start: @escaping () -> Void,
    finish: @escaping () -> Void,
    _ syncFunction: @escaping () async throws -> Void
  ) async {
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
