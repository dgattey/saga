//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var syncViewModel: SyncViewModel
  @EnvironmentObject var cachesViewModel: CachesViewModel
  @EnvironmentObject var animationSettings: AnimationSettings

  // Image cache settings
  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @State private var imageCacheLimitIndex: Double = 3

  // Network cache settings
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5
  @State private var networkCacheLimitIndex: Double = 3

  private let cacheLimitOptions: [Double] = [0.1, 0.5, 1, 5, 10, 0]

  var body: some View {
    Form {
      Section {
        animationSpringResponseSlider
        animationSpringDampingSlider
        resetAnimationButton
      } header: {
        Text("Animations")
          .font(.headline)
      }
      Section {
        CacheSectionView(
          limitLabel: "Image cache",
          limitGB: $imageCacheLimitGB,
          limitIndex: $imageCacheLimitIndex,
          currentSizeBytes: cachesViewModel.imageCacheSizeBytes,
          options: cacheLimitOptions,
          onLimitChange: {
            ImageCache.enforceDiskCacheLimit()
            cachesViewModel.refreshSizes()
          }
        )
      } header: {
        Text("Storage")
          .font(.headline)
      }
      Section {
        CacheSectionView(
          limitLabel: "Network cache",
          limitGB: $networkCacheLimitGB,
          limitIndex: $networkCacheLimitIndex,
          currentSizeBytes: cachesViewModel.networkCacheSizeBytes,
          options: cacheLimitOptions,
          onLimitChange: {
            NetworkCache.enforceCacheLimit()
            cachesViewModel.refreshSizes()
          }
        )
      }
      Section {
        allCachesRow
        localDataRow
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Settings")
    .toolbar(removing: .title)
    .accessibilityIdentifier(AccessibilityID.Settings.view)
    .safeAreaInset(edge: .top) {
      SettingsHeaderView(
        title: "Settings",
        systemImage: "gear",
        backgroundColor: Color(white: 0.5)
      )
    }
    .safeAreaInset(edge: .bottom) {
      AppInformationView()
    }
    .frame(minWidth: 400, idealWidth: 450, maxWidth: 600, minHeight: 500, maxHeight: 900)
    .onAppear {
      imageCacheLimitIndex = Double(cacheLimitOptions.firstIndex(of: imageCacheLimitGB) ?? 3)
      networkCacheLimitIndex = Double(cacheLimitOptions.firstIndex(of: networkCacheLimitGB) ?? 3)
    }
  }

  // MARK: - All Caches Row

  private var allCachesRow: some View {
    HStack {
      Text("Images and network")
      Spacer()
      Button("Clear caches", role: .destructive) {
        Task {
          await cachesViewModel.clearAll()
        }
      }
      .foregroundStyle(.red)
      .accessibilityIdentifier(AccessibilityID.Settings.clearCaches)
    }
  }

  // MARK: - Local Data Row

  private var localDataRow: some View {
    HStack {
      Text("All local data")
      Spacer()
      if syncViewModel.isResetting {
        HStack(spacing: 8) {
          ProgressView()
            .progressViewStyle(.automatic)
            .controlSize(.small)
          Text("Clearing...")
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
      } else {
        Button("Clear caches & data", role: .destructive) {
          Task {
            await cachesViewModel.clearAll()
            await syncViewModel.resetAndSync()
          }
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier(AccessibilityID.Settings.clearCachesAndData)
      }
    }
    .disabled(syncViewModel.isSyncing || syncViewModel.isResetting)
  }

  // MARK: - Animation Settings

  private var animationSpringResponseSlider: some View {
    SettingsSliderView(
      label: "Spring response",
      formattedValue: String(format: "%.2f", animationSettings.springResponse),
      value: $animationSettings.springResponse,
      range: 0.1...1.0,
      step: 0.05
    )
  }

  private var animationSpringDampingSlider: some View {
    SettingsSliderView(
      label: "Spring damping",
      formattedValue: String(format: "%.2f", animationSettings.springDamping),
      value: $animationSettings.springDamping,
      range: 0.1...1.0,
      step: 0.05
    )
  }

  private var resetAnimationButton: some View {
    HStack {
      Text("Defaults")
      Spacer()
      Button("Reset") {
        animationSettings.resetToDefaults()
      }
      .disabled(
        animationSettings.springResponse == AnimationSettings.defaultSpringResponse
          && animationSettings.springDamping == AnimationSettings.defaultSpringDamping
      )
    }
  }

}
