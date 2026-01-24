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
        .frame(maxWidth: 400, minHeight: 200)
    }
    
    var localDataRow: some View {
        HStack {
            Text("Local data")
            Spacer()
            if viewModel.isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.automatic)
                        .controlSize(.small)
                    Text("Resetting...")
                        .foregroundStyle(.secondary)
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
        .disabled(viewModel.isSyncing)
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
                .pointerStyle(.link)
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
