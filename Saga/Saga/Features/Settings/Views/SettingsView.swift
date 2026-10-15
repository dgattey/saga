//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var syncViewModel: SyncViewModel
  @EnvironmentObject var cachesViewModel: CachesViewModel
  @EnvironmentObject var animationSettings: AnimationSettings
  #if os(macOS)
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
  #endif

  @State private var selectedPane: SettingsPane

  // Image cache settings
  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @State private var imageCacheLimitIndex: Double = 3

  // Network cache settings
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5
  @State private var networkCacheLimitIndex: Double = 3

  private let cacheLimitOptions: [Double] = [0.1, 0.5, 1, 5, 10, 0]

  init(initialPane: SettingsPane = .general) {
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    Group {
      #if os(macOS)
        macOSSplitLayout
      #else
        iOSSheetLayout
      #endif
    }
    .accessibilityIdentifier(AccessibilityID.Settings.view)
    .onAppear {
      imageCacheLimitIndex = Double(cacheLimitOptions.firstIndex(of: imageCacheLimitGB) ?? 3)
      networkCacheLimitIndex = Double(cacheLimitOptions.firstIndex(of: networkCacheLimitGB) ?? 3)
      cachesViewModel.startMonitoring()
    }
    .onDisappear {
      cachesViewModel.stopMonitoring()
    }
  }

  // MARK: - Platform Layouts

  #if os(macOS)
    private var macOSSplitLayout: some View {
      HStack(spacing: 0) {
        SettingsSidebarView(selectedPane: $selectedPane)

        Rectangle()
          .fill(.quaternary)
          .frame(width: 1)

        VStack(alignment: .leading, spacing: 0) {
          SettingsHeaderView(
            title: selectedPane.title,
            subtitle: selectedPane.subtitle,
            systemImage: selectedPane.systemImage,
            backgroundColor: selectedPane.accentColor
          )

          Divider()
            .opacity(0.5)

          ScrollView(.vertical) {
            paneContent(for: selectedPane)
              .padding(20)
          }
          .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .navigationTitle("Settings")
      .toolbar(removing: .title)
      .frame(
        minWidth: 640,
        idealWidth: 680,
        maxWidth: 780,
        minHeight: 480,
        idealHeight: 560,
        maxHeight: 820
      )
    }
  #else
    private var iOSSheetLayout: some View {
      NavigationStack {
        VStack(alignment: .leading, spacing: 0) {
          SettingsHeaderView(
            title: selectedPane.title,
            subtitle: selectedPane.subtitle,
            systemImage: selectedPane.systemImage,
            backgroundColor: selectedPane.accentColor
          )

          Picker("Section", selection: $selectedPane) {
            ForEach(SettingsPane.allCases) { pane in
              Text(pane.shortTitle).tag(pane)
            }
          }
          .pickerStyle(.segmented)
          .padding(.horizontal, 20)
          .padding(.bottom, 12)

          Divider()
            .opacity(0.5)

          ScrollView(.vertical) {
            paneContent(for: selectedPane)
              .padding(20)
          }
          .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        }
        .botanicalPageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              dismiss()
            }
          }
        }
      }
    }
  #endif

  // MARK: - Pane Content

  @ViewBuilder
  func paneContent(for pane: SettingsPane) -> some View {
    switch pane {
    case .general:
      generalPaneContent
    case .storage:
      storagePaneContent
    case .credits:
      CreditsView()
    }
  }

  private var generalPaneContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      #if os(macOS)
        SettingsCard(
          title: "Updates",
          subtitle: "Keep Saga up to date automatically with Sparkle",
          systemImage: "arrow.triangle.2.circlepath"
        ) {
          automaticallyCheckForUpdatesToggle
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
          SettingsCardDivider()
          automaticallyDownloadUpdatesToggle
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
          SettingsCardDivider()
          checkForUpdatesRow
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
      #endif

      SettingsCard(
        title: "Animations",
        subtitle: "Tune interactive spring physics across the app",
        systemImage: "wand.and.rays"
      ) {
        animationSpringResponseSlider
          .padding(14)
        SettingsCardDivider()
        animationSpringDampingSlider
          .padding(14)
        SettingsCardDivider()
        resetAnimationButton
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
      }
    }
  }

  private var storagePaneContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: "Image Cache",
        subtitle: "Book cover artwork and downsampled images stored on disk",
        systemImage: "photo.stack"
      ) {
        CacheSectionView(
          limitLabel: "Image cache",
          limitGB: $imageCacheLimitGB,
          limitIndex: $imageCacheLimitIndex,
          currentSizeBytes: cachesViewModel.imageCacheSizeBytes,
          options: cacheLimitOptions,
          onLimitChange: {
            Task { @MainActor in
              await Task.detached(priority: .utility) {
                ImageCache.enforceDiskCacheLimit()
              }.value
              cachesViewModel.refreshSizes()
            }
          }
        )
        .padding(14)
      }

      SettingsCard(
        title: "Network Cache",
        subtitle: "HTTP response cache for Contentful and cover resolution APIs",
        systemImage: "network"
      ) {
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
        .padding(14)
      }

      SettingsCard(
        title: "Reset & Maintenance",
        subtitle: "Reclaim disk space or re-sync your local Core Data store",
        systemImage: "trash"
      ) {
        allCachesRow
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
        SettingsCardDivider()
        localDataRow
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
      }
    }
  }

  // MARK: - All Caches Row

  private var allCachesRow: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Images and network")
          .font(.subheadline.weight(.medium))
        Text("Removes cached covers and HTTP responses without touching books")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Clear caches", role: .destructive) {
        Task {
          await cachesViewModel.clearAll()
        }
      }
      .buttonStyle(.glass)
      .foregroundStyle(.red)
      .accessibilityIdentifier(AccessibilityID.Settings.clearCaches)
    }
  }

  // MARK: - Local Data Row

  private var localDataRow: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("All local data")
          .font(.subheadline.weight(.medium))
        Text("Wipes Core Data and re-downloads everything from Contentful")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
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
        .buttonStyle(.glass)
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
        .font(.subheadline.weight(.medium))
      Spacer()
      Button("Reset") {
        animationSettings.resetToDefaults()
      }
      .buttonStyle(.glass)
      .disabled(
        animationSettings.springResponse == AnimationSettings.defaultSpringResponse
          && animationSettings.springDamping == AnimationSettings.defaultSpringDamping
      )
    }
  }

  #if os(macOS)
    // MARK: - Update Settings

    private var automaticallyCheckForUpdatesToggle: some View {
      HStack {
        Text("Automatically check for updates")
          .font(.subheadline)
        Spacer()
        Toggle(
          "Automatically check for updates",
          isOn: $updaterViewModel.automaticallyChecksForUpdates
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!updaterViewModel.isConfigured)
        .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)
      }
    }

    private var automaticallyDownloadUpdatesToggle: some View {
      HStack {
        Text("Automatically download updates")
          .font(.subheadline)
        Spacer()
        Toggle(
          "Automatically download updates",
          isOn: $updaterViewModel.automaticallyDownloadsUpdates
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!updaterViewModel.isConfigured || !updaterViewModel.automaticallyChecksForUpdates)
        .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)
      }
    }

    private var checkForUpdatesRow: some View {
      HStack {
        Text("Software updates")
          .font(.subheadline)
        Spacer()
        Button("Check for Updates…") {
          updaterViewModel.checkForUpdates()
        }
        .buttonStyle(.glass)
        .disabled(!updaterViewModel.canCheckForUpdates)
        .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
      }
    }
  #endif
}
