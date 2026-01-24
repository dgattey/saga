//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SyncViewModel
    @State private var isHoveringAppInfo = false
    @State private var isHoveringLink = false
    @AppStorage("downsampledImageCacheLimitGB") private var cacheLimitGB: Double = 10
    @State private var cacheSizeBytes: Int64 = 0
    @State private var cacheLimitIndex: Double = 2
    private let cacheLimitOptions: [Double] = [0.5, 1, 5, 10, 20, 0]
    private let cacheRefreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var appIcon: PlatformImage? {
        let iconName = Bundle.main.iconFileName
        #if canImport(UIKit)
        let icon = iconName.flatMap { UIImage(named: $0) }
        #elseif canImport(AppKit)
        let icon = iconName.flatMap { NSImage(named: $0) }
        #endif
        return icon
    }

    var body: some View {
        Form {
            Section {
                localDataRow
            }
            Section {
                imageCacheRow
            } header: {
                Text("Storage")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .toolbar(removing: .title)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                settingsIcon
                Text("Settings")
                    .font(.largeTitleBold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            appInformation
                .padding()
        }
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500, minHeight: 520)
        .onAppear {
            refreshCacheSize()
            cacheLimitIndex = Double(cacheLimitOptions.firstIndex(of: cacheLimitGB) ?? 2)
        }
        .onReceive(cacheRefreshTimer) { _ in
            refreshCacheSize()
        }
    }
    
    var localDataRow: some View {
        HStack {
            Text("Local data")
            Spacer()
            if viewModel.isResetting {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.automatic)
                        .controlSize(.small)
                    Text("Resetting...")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                Button("Reset", role: .destructive) {
                    Task {
                        await viewModel.resetAndSync()
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .disabled(viewModel.isSyncing || viewModel.isResetting)
    }
    
    var appInformation: some View {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                if let appIcon = appIcon {
                    Image(platformImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
                Text("Saga")
                    .font(.headline)
                Text("\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .scaleEffect(isHoveringAppInfo ? 1.1 : 1.0)
            
            if isHoveringAppInfo {
                Link(destination: URL(string: "https://dylangattey.com")!) {
                    Label("More by Dylan Gattey", systemImage: "lightbulb")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isHoveringLink ? .tertiary : .quaternary)
                        )
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .pointerStyle(.link)
                #endif
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringLink = hovering
                    }
                }
                .padding(.top, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                isHoveringAppInfo = hovering
            }
        }
    }

    var imageCacheRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cache limit")
                Spacer()
                Text(cacheLimitLabel(for: cacheLimitGB))
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.quaternary)
                    )
            }
            ZStack {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 6)
                Slider(value: $cacheLimitIndex, in: 0...Double(cacheLimitOptions.count - 1), step: 1)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            HStack {
                Text("Current usage")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(cacheSizeBytes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Image cache")
                Spacer()
                Button("Clear cache", role: .destructive) {
                    DownsampledAsyncImage.clearAllCaches()
                    refreshCacheSize()
                }
                .foregroundStyle(.red)
            }
        }
        .onChange(of: cacheLimitGB) { _, _ in
            DownsampledAsyncImage.enforceDiskCacheLimit()
            refreshCacheSize()
        }
        .onChange(of: cacheLimitIndex) { _, newValue in
            let index = max(0, min(cacheLimitOptions.count - 1, Int(newValue.rounded())))
            let newLimit = cacheLimitOptions[index]
            if cacheLimitGB != newLimit {
                cacheLimitGB = newLimit
            }
        }
    }

    private func refreshCacheSize() {
        cacheSizeBytes = DownsampledAsyncImage.diskCacheSizeBytes()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func cacheLimitLabel(for value: Double) -> String {
        if value == 0 {
            return "Unlimited"
        }
        if value < 1 {
            return "\(Int(value * 1000)) MB"
        }
        return "\(Int(value)) GB"
    }
    
    var settingsIcon: some View {
        let iconSize: CGFloat = 28
        let cornerRadius: CGFloat = iconSize * 0.36 // macOS Settings icon style
        
        return Image(systemName: "gear")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: iconSize, height: iconSize)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
