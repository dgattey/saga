//
//  SyncViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

import SwiftUI

/// Handles syncing data across the full app, delegating to service functions as needed
class SyncViewModel: ObservableObject {
    private var controller = PersistenceController()
    @Published var isSyncing = false
    private var syncTask: Task<Void, Never>?
    
    var viewContext: NSManagedObjectContext {
        return controller.container.viewContext
    }
    
    /// Syncs if there's no sync running already
    func sync() async {
        await orchestrateSync { [weak self] in
            try await self?.controller.syncWithApi()
        }
    }
    
    /// Resets all data, then syncs as long as there's no sync running already
    func resetAndSync() async {
        await orchestrateSync { [weak self] in
            try await self?.controller.resetAndSyncWithApi()
        }
    }
    
    /// Helper to orchestrate some sync function, managing state as it does so
    private func orchestrateSync(_ syncFunction: @escaping () async throws -> Void) async {
        guard !isSyncing else { return }
        syncTask = Task(priority: .background) {
            await MainActor.run {
                isSyncing = true
            }
            do {
                try await syncFunction()
                await MainActor.run {
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                }
                print("Error syncing: \(error)")
            }
        }
    }
}
