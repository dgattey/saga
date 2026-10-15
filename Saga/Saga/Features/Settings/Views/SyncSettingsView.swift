//
//  SyncSettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import SwiftUI

struct SyncSettingsView: View {
  @EnvironmentObject var syncViewModel: SyncViewModel

  @AppStorage(GoodreadsSyncService.syncURLStorageKey) private var syncURLOverride = ""
  @AppStorage(GoodreadsSyncService.syncSecretStorageKey) private var syncSecretOverride = ""

  private var effectiveSyncURL: String {
    GoodreadsSyncService.configuredSyncURLString
  }

  private var isConfigured: Bool {
    !effectiveSyncURL.isEmpty
  }

  var body: some View {
    Section {
      statusRow
      endpointURLRow
      secretRow
      syncNowRow
    } header: {
      Text("Goodreads Sync")
        .font(.headline)
    }
  }

  // MARK: - Subviews

  private var statusRow: some View {
    HStack {
      Text("Status")
      Spacer()
      if syncViewModel.isSyncing {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text("Syncing...")
            .foregroundStyle(.secondary)
        }
      } else if let summary = syncViewModel.lastGoodreadsSyncSummary {
        Text(
          "Synced (+\(summary.createdCount ?? 0), Δ\(summary.updatedCount ?? 0), =\(summary.skippedCount ?? 0))"
        )
        .foregroundStyle(.secondary)
      } else {
        Text(isConfigured ? "Configured" : "Not configured")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var endpointURLRow: some View {
    TextField(
      "Endpoint URL",
      text: $syncURLOverride,
      prompt: Text(
        BundleKey.goodreadsSyncURL.bundleValue.isEmpty
          ? "https://<app>.vercel.app/api/cron/goodreads-sync"
          : BundleKey.goodreadsSyncURL.bundleValue
      )
    )
    .textFieldStyle(.roundedBorder)
  }

  private var secretRow: some View {
    SecureField(
      "Bearer secret",
      text: $syncSecretOverride,
      prompt: Text(
        BundleKey.goodreadsSyncSecret.bundleValue.isEmpty
          ? "Optional CRON_SECRET"
          : "Configured via Config.xcconfig"
      )
    )
    .textFieldStyle(.roundedBorder)
  }

  private var syncNowRow: some View {
    HStack {
      Text("Manual sync")
      Spacer()
      Button("Sync now") {
        Task {
          await syncViewModel.syncWithContentful()
        }
      }
      .disabled(syncViewModel.isSyncing || syncViewModel.isResetting)
    }
  }
}
