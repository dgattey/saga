//
//  StorageSettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/16/26.
//

import SwiftUI

/// Disk cache limits plus maintenance actions for caches and the local Core Data store.
struct StorageSettingsView: View {
  @Environment(SyncViewModel.self) var syncViewModel
  @Environment(CachesViewModel.self) var cachesViewModel

  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5

  var body: some View {
    Form {
      Section("Cache Limits") {
        CacheLimitRow(
          title: "Image cache",
          limitGB: $imageCacheLimitGB,
          currentSizeBytes: cachesViewModel.imageCacheSizeBytes,
          onLimitChange: {
            Task { @MainActor in
              await Task.detached(priority: .utility) {
                ImageCache.enforceDiskCacheLimit()
              }.value
              cachesViewModel.refreshSizes()
            }
          }
        )
        CacheLimitRow(
          title: "Network cache",
          limitGB: $networkCacheLimitGB,
          currentSizeBytes: cachesViewModel.networkCacheSizeBytes,
          onLimitChange: {
            NetworkCache.enforceCacheLimit()
            cachesViewModel.refreshSizes()
          }
        )
      }

      Section("Maintenance") {
        LabeledContent {
          Button("Clear Caches", role: .destructive) {
            Task {
              await cachesViewModel.clearAll()
            }
          }
          .foregroundStyle(Color.botanicalTerracotta)
          .accessibilityIdentifier(AccessibilityID.Settings.clearCaches)
        } label: {
          Text("Cached covers & responses")
          Text("Keeps your synced books")
        }

        LabeledContent {
          if syncViewModel.isResetting {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Resetting…")
                .foregroundStyle(.secondary)
            }
          } else {
            Button("Reset & Re-sync", role: .destructive) {
              Task {
                await cachesViewModel.clearAll()
                await syncViewModel.resetAndSync()
              }
            }
            .foregroundStyle(Color.botanicalTerracotta)
            .accessibilityIdentifier(AccessibilityID.Settings.clearCachesAndData)
          }
        } label: {
          Text("All local data")
          Text("Re-downloads everything from Contentful")
        }
        .disabled(syncViewModel.isSyncing || syncViewModel.isResetting)
      }
    }
  }
}
