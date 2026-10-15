//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import CoreData
import SwiftUI

/// Handles syncing data across the full app, delegating to service functions as needed
final class SyncViewModel: ObservableObject {
  private var controller = PersistenceService()
  @Published var isSyncing = false
  @Published var isResetting = false
  @Published var resetToken = UUID()
  @Published private(set) var lastGoodreadsSyncSummary: GoodreadsSyncResponse?
  @Published private(set) var lastSyncDate: Date?
  private var syncTask: Task<Void, Never>?

  var viewContext: NSManagedObjectContext {
    return controller.container.viewContext
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
        if let response = await GoodreadsSyncService.triggerIfConfigured() {
          await MainActor.run {
            self.lastGoodreadsSyncSummary = response
          }
        }
        try await self.controller.syncWithApi()
        await MainActor.run {
          self.lastSyncDate = Date()
        }
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
        guard let self else { return }
        if let response = await GoodreadsSyncService.triggerIfConfigured() {
          await MainActor.run {
            self.lastGoodreadsSyncSummary = response
          }
        }
        try await self.controller.resetAndSyncWithApi()
        await MainActor.run {
          self.lastSyncDate = Date()
        }
      }
    )
  }

  /// Helper to orchestrate some sync function, managing state as it does so
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
