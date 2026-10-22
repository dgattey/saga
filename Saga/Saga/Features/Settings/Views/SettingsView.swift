//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(CachesViewModel.self) private var cachesViewModel: CachesViewModel?
  @State private var selectedPane: SettingsPane

  init(initialPane: SettingsPane = LaunchOptions.settingsPane ?? .general) {
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    Group {
      #if os(macOS)
        NavigationSplitView {
          List(selection: $selectedPane) {
            ForEach(SettingsPaneSection.allCases) { section in
              if let title = section.title {
                Section(title) {
                  ForEach(section.panes) { pane in
                    paneLabel(for: pane)
                      .tag(pane)
                  }
                }
              } else {
                ForEach(section.panes) { pane in
                  paneLabel(for: pane)
                    .tag(pane)
                }
              }
            }
          }
          .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
          .navigationSplitViewColumnWidth(195)
          .toolbar(removing: .sidebarToggle)
        } detail: {
          paneForm(for: selectedPane)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(width: 700, height: 540)
      #else
        NavigationStack {
          Form {
            SettingsAboutSections()
            SettingsSyncSections()
            SettingsStorageSections()
            SettingsAnimationsSections()
            Section("App") {
              NavigationLink {
                creditsForm
              } label: {
                Label {
                  Text("Credits & Acknowledgements")
                } icon: {
                  SettingsPaneBadge(pane: .credits)
                }
              }
              .accessibilityIdentifier(AccessibilityID.Settings.pane(SettingsPane.credits.id))
            }
          }
          .formStyle(.grouped)
          .tint(Color.botanicalDeepMoss)
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
          .navigationDestination(for: SettingsPane.self) { pane in
            paneForm(for: pane)
          }
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") {
                dismiss()
              }
            }
          }
        }
      #endif
    }
    .accessibilityIdentifier(AccessibilityID.Settings.view)
    .onAppear {
      cachesViewModel?.startMonitoring()
    }
    .onDisappear {
      cachesViewModel?.stopMonitoring()
    }
  }

  private func paneLabel(for pane: SettingsPane) -> some View {
    Label {
      Text(pane.title)
    } icon: {
      SettingsPaneBadge(pane: pane)
    }
    .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.id))
  }

  func paneForm(for pane: SettingsPane) -> some View {
    SettingsPaneFormView(pane: pane)
  }

  var creditsForm: some View {
    Form {
      SettingsCreditsSections()
    }
    .formStyle(.grouped)
    .tint(Color.botanicalDeepMoss)
    .navigationTitle(SettingsPane.credits.title)
  }

  // MARK: - Formatting

  static let cacheLimitOptions: [Double] = CacheLimitRow.limitOptions

  static func formatBytes(_ bytes: Int64) -> String {
    CacheLimitRow.formatBytes(bytes)
  }

  static func formatLimit(_ value: Double) -> String {
    CacheLimitRow.formatLimit(value)
  }
}

// MARK: - Pane Form

private struct SettingsPaneFormView: View {
  let pane: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      #if os(macOS)
        SettingsHeaderView(pane: pane)
      #endif

      Form {
        switch pane {
        case .general:
          SettingsGeneralSections()
        case .sync:
          SettingsSyncSections()
        case .storage:
          SettingsStorageSections()
        case .animations:
          SettingsAnimationsSections()
        case .credits:
          SettingsCreditsSections()
        case .about:
          SettingsAboutSections()
        }
      }
      .formStyle(.grouped)
      .tint(Color.botanicalDeepMoss)
    }
    .navigationTitle(pane.title)
  }
}

// MARK: - General Sections

private struct SettingsGeneralSections: View {
  #if os(macOS)
    @Environment(UpdaterViewModel.self) private var injectedUpdaterViewModel: UpdaterViewModel?
  #endif

  var body: some View {
    Section("Software Updates") {
      #if os(macOS)
        if let updaterViewModel = injectedUpdaterViewModel {
          Toggle(
            "Automatically check for updates",
            isOn: Bindable(updaterViewModel).automaticallyChecksForUpdates
          )
          .disabled(!updaterViewModel.isConfigured)
          .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)

          Toggle(
            "Automatically download updates",
            isOn: Bindable(updaterViewModel).automaticallyDownloadsUpdates
          )
          .disabled(
            !updaterViewModel.isConfigured || !updaterViewModel.automaticallyChecksForUpdates
          )
          .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)

          LabeledContent {
            Button("Check for Updates…") {
              updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
            .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
          } label: {
            Text("Software updates")
            Text("Current version v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
          }
        } else {
          fallbackUpdateRows
        }
      #else
        fallbackUpdateRows
      #endif
    }
  }

  @ViewBuilder
  private var fallbackUpdateRows: some View {
    Toggle("Automatically check for updates", isOn: .constant(true))
      .disabled(true)
      .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)

    Toggle("Automatically download updates", isOn: .constant(false))
      .disabled(true)
      .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)

    LabeledContent {
      Button("Check for Updates…") {}
        .disabled(true)
        .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
    } label: {
      Text("Software updates")
      Text("Current version v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
    }
  }
}

// MARK: - Sync Sections

private struct SettingsSyncSections: View {
  @Environment(SyncViewModel.self) private var injectedSyncViewModel: SyncViewModel?
  @Environment(CachesViewModel.self) private var injectedCachesViewModel: CachesViewModel?

  private var isSyncing: Bool {
    injectedSyncViewModel?.isSyncing ?? false
  }

  private var isResetting: Bool {
    injectedSyncViewModel?.isResetting ?? false
  }

  var body: some View {
    Section("Library Sync") {
      LabeledContent {
        if isSyncing {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Syncing…")
              .foregroundStyle(.secondary)
          }
        } else {
          Button("Sync Now") {
            guard let syncViewModel = injectedSyncViewModel else { return }
            Task {
              await syncViewModel.sync()
            }
          }
          .accessibilityIdentifier(AccessibilityID.Settings.syncNow)
        }
      } label: {
        Text("Contentful & Goodreads")
        Text("Pulls latest shelves, books, and reviews")
      }
      .disabled(isSyncing || isResetting)

      LabeledContent {
        if isResetting {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Resetting…")
              .foregroundStyle(.secondary)
          }
        } else {
          Button("Reset & Re-sync", role: .destructive) {
            Task {
              await injectedCachesViewModel?.clearAll()
              await injectedSyncViewModel?.resetAndSync()
            }
          }
          .accessibilityIdentifier(AccessibilityID.Settings.clearCachesAndData)
        }
      } label: {
        Text("Reset local library")
        Text("Clears local database and re-downloads all books from Contentful")
      }
      .disabled(isSyncing || isResetting)
    }
  }
}

// MARK: - Storage Sections

private struct SettingsStorageSections: View {
  @Environment(CachesViewModel.self) private var injectedCachesViewModel: CachesViewModel?
  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5

  private var imageCacheSizeBytes: Int64 {
    injectedCachesViewModel?.imageCacheSizeBytes ?? 0
  }

  private var networkCacheSizeBytes: Int64 {
    injectedCachesViewModel?.networkCacheSizeBytes ?? 0
  }

  var body: some View {
    Section("Cache Limits") {
      CacheLimitRow(
        title: "Image cache",
        limitGB: $imageCacheLimitGB,
        currentSizeBytes: imageCacheSizeBytes
      ) {
        Task { @MainActor in
          await Task.detached(priority: .utility) {
            ImageCache.enforceDiskCacheLimit()
          }.value
          injectedCachesViewModel?.refreshSizes()
        }
      }

      CacheLimitRow(
        title: "Network cache",
        limitGB: $networkCacheLimitGB,
        currentSizeBytes: networkCacheSizeBytes
      ) {
        NetworkCache.enforceCacheLimit()
        injectedCachesViewModel?.refreshSizes()
      }
    }

    Section("Maintenance") {
      LabeledContent {
        Button("Clear Caches", role: .destructive) {
          Task {
            await injectedCachesViewModel?.clearAll()
          }
        }
        .accessibilityIdentifier(AccessibilityID.Settings.clearCaches)
      } label: {
        Text("Cached covers & responses")
        Text("Frees disk space without removing synced books")
      }
    }
  }
}

// MARK: - Animations Sections

private struct SettingsAnimationsSections: View {
  @Environment(AnimationSettings.self) private var injectedAnimationSettings: AnimationSettings?

  private var animationSettings: AnimationSettings {
    injectedAnimationSettings ?? .shared
  }

  private var isAnimationAtDefaults: Bool {
    animationSettings.springResponse == AnimationSettings.defaultSpringResponse
      && animationSettings.springDamping == AnimationSettings.defaultSpringDamping
  }

  var body: some View {
    Section("Motion & Animations") {
      springSliderRow(
        "Spring response",
        subtitle: "How quickly interface elements reach their target",
        value: Bindable(animationSettings).springResponse
      )
      springSliderRow(
        "Spring damping",
        subtitle: "How much bounce settles at the end of a motion",
        value: Bindable(animationSettings).springDamping
      )
      LabeledContent {
        Button("Reset to Defaults") {
          animationSettings.resetToDefaults()
        }
        .disabled(isAnimationAtDefaults)
        .accessibilityIdentifier(AccessibilityID.Settings.resetAnimations)
      } label: {
        Text("Defaults")
        Text("0.30 response · 0.70 damping")
      }
    }
  }

  private func springSliderRow(
    _ title: String,
    subtitle: String,
    value: Binding<Double>
  ) -> some View {
    LabeledContent {
      HStack(spacing: 10) {
        Slider(value: value, in: 0.1...1.0, step: 0.05)
          .labelsHidden()
          #if os(macOS)
            .frame(maxWidth: 170)
          #else
            .frame(maxWidth: 130)
          #endif

        Text(String(format: "%.2f", value.wrappedValue))
          .font(.caption.monospaced().weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.botanicalLeaf.opacity(0.10), in: Capsule())
          .overlay(
            Capsule()
              .strokeBorder(Color.botanicalLeaf.opacity(0.22), lineWidth: 1)
          )
          .frame(minWidth: 46, alignment: .trailing)
      }
    } label: {
      Text(title)
      Text(subtitle)
    }
  }
}

// MARK: - About Sections

private struct SettingsAboutSections: View {
  var body: some View {
    Section {
      AppInformationView()
    }
  }
}

// MARK: - Badges

/// A small colored squircle with a white SF Symbol, matching System Settings / Notch sidebar icons.
struct SettingsIconBadge: View {
  let systemImage: String
  let color: Color

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 22, height: 22)
      .background(color.gradient, in: .rect(cornerRadius: 6, style: .continuous))
  }
}

/// Sidebar badge for a top-level `SettingsPane`.
struct SettingsPaneBadge: View {
  let pane: SettingsPane

  var body: some View {
    SettingsIconBadge(systemImage: pane.systemImage, color: pane.badgeColor)
  }
}
