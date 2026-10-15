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

  private var isConfigured: Bool {
    GoodreadsSyncService.isConfigured
  }

  var body: some View {
    Section {
      statusRow
      endpointURLRow
      secretRow
      syncNowRow
    } header: {
      Text("Goodreads & Contentful Server")
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
          "Synced (+\(summary.effectiveCreatedCount), Δ\(summary.effectiveUpdatedCount), =\(summary.effectiveSkippedCount))"
        )
        .foregroundStyle(.secondary)
      } else {
        Text(isConfigured ? "Configured (HMAC-SHA256)" : "Secret not configured")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var endpointURLRow: some View {
    TextField(
      "Server URL",
      text: $syncURLOverride,
      prompt: Text(
        BundleKey.goodreadsSyncURL.bundleValue.isEmpty
          ? GoodreadsSyncService.defaultServerOrigin
          : BundleKey.goodreadsSyncURL.bundleValue
      )
    )
    .textFieldStyle(.roundedBorder)
  }

  private var secretRow: some View {
    SecureField(
      "API secret",
      text: $syncSecretOverride,
      prompt: Text(
        BundleKey.goodreadsSyncSecret.bundleValue.isEmpty
          ? "SAGA_API_SECRET / CRON_SECRET"
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
