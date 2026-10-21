//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SyncViewModel.self) var syncViewModel
  @Environment(CachesViewModel.self) var cachesViewModel
  @Environment(AnimationSettings.self) var animationSettings
  #if os(macOS)
    @Environment(UpdaterViewModel.self) var updaterViewModel
  #endif

  @AppStorage(ImageCache.cacheLimitKey) private var imageCacheLimitGB: Double = 5
  @AppStorage(NetworkCache.cacheLimitKey) private var networkCacheLimitGB: Double = 5
  @State private var selectedPane: SettingsPane = .general

  init(initialPane: SettingsPane = .general) {
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
          List(SettingsPane.allCases) { pane in
            NavigationLink(value: pane) {
              paneLabel(for: pane)
            }
          }
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
      cachesViewModel.startMonitoring()
    }
    .onDisappear {
      cachesViewModel.stopMonitoring()
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
    Form {
      switch pane {
      case .general:
        generalSections
      case .storage:
        storageSections
      case .credits:
        creditsSections
      case .about:
        aboutSections
      }
    }
    .formStyle(.grouped)
    .tint(Color.botanicalDeepMoss)
    .navigationTitle(pane.title)
  }

  // MARK: - General

  @ViewBuilder
  private var generalSections: some View {
    #if os(macOS)
      Section("Updates") {
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
      }
    #endif

    Section("Animations") {
      springSliderRow("Spring response", value: Bindable(animationSettings).springResponse)
      springSliderRow("Spring damping", value: Bindable(animationSettings).springDamping)
      LabeledContent("Defaults") {
        Button("Reset") {
          animationSettings.resetToDefaults()
        }
        .disabled(isAnimationAtDefaults)
      }
    }
  }

  private var isAnimationAtDefaults: Bool {
    animationSettings.springResponse == AnimationSettings.defaultSpringResponse
      && animationSettings.springDamping == AnimationSettings.defaultSpringDamping
  }

  private func springSliderRow(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        Slider(value: value, in: 0.1...1.0)
          .labelsHidden()
          .frame(maxWidth: 180)
        Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
      }
    }
  }

  // MARK: - Storage

  @ViewBuilder
  private var storageSections: some View {
    Section("Cache Limits") {
      cacheLimitPicker(
        title: "Image cache",
        limitGB: $imageCacheLimitGB,
        currentSizeBytes: cachesViewModel.imageCacheSizeBytes
      ) {
        Task { @MainActor in
          await Task.detached(priority: .utility) {
            ImageCache.enforceDiskCacheLimit()
          }.value
          cachesViewModel.refreshSizes()
        }
      }

      cacheLimitPicker(
        title: "Network cache",
        limitGB: $networkCacheLimitGB,
        currentSizeBytes: cachesViewModel.networkCacheSizeBytes
      ) {
        NetworkCache.enforceCacheLimit()
        cachesViewModel.refreshSizes()
      }
    }

    Section("Maintenance") {
      LabeledContent {
        Button("Clear Caches", role: .destructive) {
          Task {
            await cachesViewModel.clearAll()
          }
        }
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
          .accessibilityIdentifier(AccessibilityID.Settings.clearCachesAndData)
        }
      } label: {
        Text("All local data")
        Text("Re-downloads everything from Contentful")
      }
      .disabled(syncViewModel.isSyncing || syncViewModel.isResetting)
    }
  }

  static let cacheLimitOptions: [Double] = [0.1, 0.5, 1, 5, 10, 0]

  private func cacheLimitPicker(
    title: String,
    limitGB: Binding<Double>,
    currentSizeBytes: Int64,
    onLimitChange: @escaping () -> Void
  ) -> some View {
    Picker(selection: limitGB) {
      ForEach(Self.cacheLimitOptions, id: \.self) { option in
        Text(Self.formatLimit(option)).tag(option)
      }
    } label: {
      Text(title)
      Text("\(Self.formatBytes(currentSizeBytes)) used")
    }
    .onChange(of: limitGB.wrappedValue) { _, _ in
      onLimitChange()
    }
  }

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

  // MARK: - Credits

  @ViewBuilder
  private var creditsSections: some View {
    Section("Data") {
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

  // MARK: - About

  @ViewBuilder
  private var aboutSections: some View {
    Section {
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

/// A small colored squircle with a white SF Symbol, matching System Settings sidebar icons.
struct SettingsPaneBadge: View {
  let pane: SettingsPane

  var body: some View {
    Image(systemName: pane.systemImage)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(pane.badgeColor, in: .rect(cornerRadius: 5, style: .continuous))
  }
}
