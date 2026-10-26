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
  #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
  #endif

  init(initialPane: SettingsPane = LaunchOptions.settingsPane ?? .general) {
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    Group {
      #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
          SettingsSidebarView(selectedPane: $selectedPane)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 205, ideal: 205, max: 205)
        } detail: {
          paneForm(for: selectedPane)
            .toolbar {
              ToolbarItem(placement: .navigation) {
                SettingsHeaderView(pane: selectedPane)
              }
              .sharedBackgroundVisibility(.hidden)
            }
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
}

// MARK: - macOS Sidebar

#if os(macOS)
  private struct SettingsSidebarView: View {
    @Environment(AnimationSettings.self) private var injectedAnimationSettings: AnimationSettings?
    @Binding var selectedPane: SettingsPane

    private var animationSettings: AnimationSettings {
      injectedAnimationSettings ?? .shared
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        ForEach(SettingsPaneSection.allCases) { section in
          if let title = section.title {
            Text(title)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fontWeight(.medium)
              .padding(.top, 10)
              .padding(.bottom, 5)
              .padding(.horizontal, 15)
          }
          ForEach(section.panes) { pane in
            sidebarRow(for: pane)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
    }

    private func sidebarRow(for pane: SettingsPane) -> some View {
      let isSelected = selectedPane == pane

      return Button {
        withAnimation(animationSettings.selectionSpring) {
          selectedPane = pane
        }
      } label: {
        HStack(alignment: .center, spacing: 8) {
          SettingsPaneBadge(pane: pane)
          Text(pane.title)
            .font(.body)
            .foregroundStyle(.primary)
          Spacer(minLength: 0)
        }
        .padding(7)
        .background(
          isSelected ? Color.primary.opacity(0.11) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(AccessibilityID.Settings.pane(pane.id))
    }
  }
#endif

// MARK: - Pane Form

private struct SettingsPaneFormView: View {
  let pane: SettingsPane

  var body: some View {
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
    #if os(macOS)
      .scrollContentBackground(.hidden)
      .scrollEdgeEffectStyle(.soft, for: .top)
      .navigationTitle("")
    #else
      .navigationTitle(pane.title)
    #endif
  }
}

// MARK: - General Sections

private struct SettingsGeneralSections: View {
  #if os(macOS)
    @Environment(UpdaterViewModel.self) private var injectedUpdaterViewModel: UpdaterViewModel?
  #endif

  private var automaticallyChecksBinding: Binding<Bool> {
    #if os(macOS)
      if let updaterViewModel = injectedUpdaterViewModel {
        return Bindable(updaterViewModel).automaticallyChecksForUpdates
      }
    #endif
    return .constant(true)
  }

  private var automaticallyDownloadsBinding: Binding<Bool> {
    #if os(macOS)
      if let updaterViewModel = injectedUpdaterViewModel {
        return Bindable(updaterViewModel).automaticallyDownloadsUpdates
      }
    #endif
    return .constant(false)
  }

  private var isConfigured: Bool {
    #if os(macOS)
      return injectedUpdaterViewModel?.isConfigured ?? false
    #else
      return false
    #endif
  }

  private var canCheckForUpdates: Bool {
    #if os(macOS)
      return injectedUpdaterViewModel?.canCheckForUpdates ?? false
    #else
      return false
    #endif
  }

  var body: some View {
    Section("Software Updates") {
      Toggle("Automatically check for updates", isOn: automaticallyChecksBinding)
        .disabled(!isConfigured)
        .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)

      Toggle("Automatically download updates", isOn: automaticallyDownloadsBinding)
        .disabled(!isConfigured || !automaticallyChecksBinding.wrappedValue)
        .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)

      LabeledContent {
        Button("Check for Updates…") {
          #if os(macOS)
            injectedUpdaterViewModel?.checkForUpdates()
          #endif
        }
        .disabled(!canCheckForUpdates)
        .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
      } label: {
        Text("Software updates")
        Text("Current version \(Bundle.main.formattedVersion)")
      }
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
          .botanicalCapsulePill()
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

/// A small colored squircle with a white SF Symbol, matching Tuneful / System Settings icons.
struct SettingsIconBadge: View {
  let systemImage: String
  let color: Color
  var size: CGFloat = 20

  private var cornerRadius: CGFloat {
    round(size * 0.28)
  }

  private var fontSize: CGFloat {
    round(size * 0.52)
  }

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: fontSize, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: .rect(cornerRadius: cornerRadius, style: .continuous))
  }
}

/// Sidebar badge for a top-level `SettingsPane`.
struct SettingsPaneBadge: View {
  let pane: SettingsPane

  var body: some View {
    SettingsIconBadge(systemImage: pane.systemImage, color: pane.badgeColor, size: 20)
  }
}
