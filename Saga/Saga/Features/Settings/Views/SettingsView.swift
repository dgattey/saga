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

  init(initialPane: SettingsPane = LaunchOptions.settingsPane ?? .storage) {
    _selectedPane = State(initialValue: initialPane)
  }

  var body: some View {
    Group {
      #if os(macOS)
        NavigationSplitView {
          List(SettingsPane.allCases, selection: $selectedPane) { pane in
            paneLabel(for: pane)
              .tag(pane)
          }
          .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
          .navigationSplitViewColumnWidth(190)
        } detail: {
          paneForm(for: selectedPane)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(width: 680, height: 520)
      #else
        NavigationStack {
          Form {
            SettingsStorageSections()
            SettingsInterfaceSections()
            Section("About") {
              SettingsAboutInfoRows()
              NavigationLink {
                creditsForm
              } label: {
                Label {
                  Text("Credits & Acknowledgements")
                } icon: {
                  SettingsIconBadge(
                    systemImage: "heart",
                    color: SettingsPane.creditsBadgeColor
                  )
                }
              }
              .accessibilityIdentifier(AccessibilityID.Settings.pane("credits"))
            }
            SettingsLinksSection()
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
    .navigationTitle("Credits")
  }

  // MARK: - Formatting

  static let cacheLimitOptions: [Double] = [0.1, 0.5, 1, 5, 10, 0]

  static func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  static func formatLimit(_ value: Double) -> String {
    if value == 0 {
      return "Unlimited"
    }
    let megabytes = Int(value * 1000)
    if megabytes < 1000 {
      return "\(megabytes) MB"
    }
    return "\(Int(value)) GB"
  }
}

// MARK: - Pane Form

private struct SettingsPaneFormView: View {
  let pane: SettingsPane

  var body: some View {
    Form {
      switch pane {
      case .storage:
        SettingsStorageSections()
      case .interface:
        SettingsInterfaceSections()
      case .about:
        SettingsAboutSections()
      }
    }
    .formStyle(.grouped)
    .tint(Color.botanicalDeepMoss)
    .navigationTitle(pane.title)
  }
}

// MARK: - Data & Storage Sections

private struct SettingsStorageSections: View {
  @Environment(SyncViewModel.self) private var injectedSyncViewModel: SyncViewModel?
  @Environment(CachesViewModel.self) private var injectedCachesViewModel: CachesViewModel?
  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5

  private var isSyncing: Bool {
    injectedSyncViewModel?.isSyncing ?? false
  }

  private var isResetting: Bool {
    injectedSyncViewModel?.isResetting ?? false
  }

  private var imageCacheSizeBytes: Int64 {
    injectedCachesViewModel?.imageCacheSizeBytes ?? 0
  }

  private var networkCacheSizeBytes: Int64 {
    injectedCachesViewModel?.networkCacheSizeBytes ?? 0
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

    Section("Local Caches") {
      cacheLimitPicker(
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

      cacheLimitPicker(
        title: "Network cache",
        limitGB: $networkCacheLimitGB,
        currentSizeBytes: networkCacheSizeBytes
      ) {
        NetworkCache.enforceCacheLimit()
        injectedCachesViewModel?.refreshSizes()
      }

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

  private func cacheLimitPicker(
    title: String,
    limitGB: Binding<Double>,
    currentSizeBytes: Int64,
    onLimitChange: @escaping () -> Void
  ) -> some View {
    Picker(selection: limitGB) {
      ForEach(SettingsView.cacheLimitOptions, id: \.self) { option in
        Text(SettingsView.formatLimit(option)).tag(option)
      }
    } label: {
      Text(title)
      Text("\(SettingsView.formatBytes(currentSizeBytes)) used")
    }
    .onChange(of: limitGB.wrappedValue) { _, _ in
      onLimitChange()
    }
  }
}

// MARK: - Interface Sections

private struct SettingsInterfaceSections: View {
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
      springSliderRow("Spring response", value: Bindable(animationSettings).springResponse)
      springSliderRow("Spring damping", value: Bindable(animationSettings).springDamping)
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

  private func springSliderRow(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        Slider(value: value, in: 0.1...1.0)
          .labelsHidden()
          #if os(macOS)
            .frame(maxWidth: 180)
          #else
            .frame(maxWidth: 140)
          #endif
        Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
      }
    }
  }
}

// MARK: - About & Credits Sections

private struct SettingsAboutSections: View {
  #if os(macOS)
    @Environment(UpdaterViewModel.self) private var injectedUpdaterViewModel: UpdaterViewModel?
  #endif

  var body: some View {
    Section("Application") {
      SettingsAboutInfoRows()
    }

    #if os(macOS)
      Section("Software Updates") {
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

          LabeledContent("Software updates") {
            Button("Check for Updates…") {
              updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
            .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
          }
        } else {
          Toggle("Automatically check for updates", isOn: .constant(true))
            .disabled(true)
            .accessibilityIdentifier(AccessibilityID.Settings.automaticallyCheckForUpdates)

          Toggle("Automatically download updates", isOn: .constant(false))
            .disabled(true)
            .accessibilityIdentifier(AccessibilityID.Settings.automaticallyDownloadUpdates)

          LabeledContent("Software updates") {
            Button("Check for Updates…") {}
              .disabled(true)
              .accessibilityIdentifier(AccessibilityID.Settings.checkForUpdates)
          }
        }
      }
    #endif

    SettingsLinksSection()
    SettingsCreditsSections()
  }
}

private struct SettingsAboutInfoRows: View {
  var body: some View {
    LabeledContent("Application") {
      Text("Saga")
    }
    LabeledContent("Version") {
      Text("\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
        .monospacedDigit()
    }
    LabeledContent("Author") {
      Text("Dylan Gattey")
    }
  }
}

private struct SettingsLinksSection: View {
  var body: some View {
    Section("Links") {
      ForEach(QuickLinkItem.all) { item in
        LabeledContent {
          Link(item.url.host() ?? item.url.absoluteString, destination: item.url)
        } label: {
          Label(item.title, systemImage: item.systemImage)
        }
      }
    }
  }
}

private struct SettingsCreditsSections: View {
  var body: some View {
    Section("Services & Data") {
      ForEach(CreditItem.dataAndAPIs) { item in
        creditRow(for: item)
      }
    }
    .accessibilityIdentifier(AccessibilityID.Settings.creditsView)

    Section("Open Source") {
      ForEach(CreditItem.openSourceLibraries) { item in
        creditRow(for: item)
      }
    }
  }

  private func creditRow(for item: CreditItem) -> some View {
    LabeledContent {
      HStack(spacing: 10) {
        if let badgeURL = item.badgeURL {
          Link(item.badge, destination: badgeURL)
            .font(.callout.monospaced())
        } else {
          Text(item.badge)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }
        Link(destination: item.url) {
          Image(systemName: "arrow.up.right")
            .font(.caption.weight(.semibold))
        }
        .accessibilityLabel("Open \(item.name)")
      }
    } label: {
      Label {
        Text(creditTitle(for: item))
        Text(item.subtitle)
      } icon: {
        Image(systemName: item.systemImage)
      }
    }
  }

  private func creditTitle(for item: CreditItem) -> String {
    guard let version = item.version else {
      return item.name
    }
    return "\(item.name) · v\(version)"
  }
}

// MARK: - Badges

/// A small colored squircle with a white SF Symbol, matching System Settings sidebar icons.
struct SettingsIconBadge: View {
  let systemImage: String
  let color: Color

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(color, in: .rect(cornerRadius: 5, style: .continuous))
  }
}

/// Sidebar badge for a top-level `SettingsPane`.
struct SettingsPaneBadge: View {
  let pane: SettingsPane

  var body: some View {
    SettingsIconBadge(systemImage: pane.systemImage, color: pane.badgeColor)
  }
}
