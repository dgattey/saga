//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var resetLocalDataTask: Task<Void, Never>? = nil
    @State private var isResettingLocalData = false
    
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
            VStack(spacing: 24) {
                appInformation
                resetLocalDataButton
            }
        }
        .navigationTitle("Settings")
        .scenePadding()
        .frame(maxWidth: 350, minHeight: 100)
    }
    
    var resetLocalDataButton: some View {
        Button(action: {
            isResettingLocalData = true
            resetLocalDataTask?.cancel()
            resetLocalDataTask = Task {
                do {
                    try await PersistenceController.shared.resetAndSyncWithApi()
                    if !Task.isCancelled {
                        await MainActor.run { isResettingLocalData = false }
                    }
                } catch {
                    print("Error resetting local data: \(error)")
                }
            }
        }) {
            HStack(spacing: 8) {
                if isResettingLocalData {
                    ProgressView()
                        .progressViewStyle(.automatic)
                        .controlSize(.small)
                    Text("Resetting...")
                } else {
                    Text("Reset all local data")
                }
            }
        }
        .disabled(isResettingLocalData)
    }
    
    var appInformation: some View {
        HStack(spacing: 16) {
            if let appIcon = appIcon {
                Image(platformImage: appIcon).resizable().frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Saga").font(.largeTitle)
                Text("Dylan Gattey").font(.subheadline)
            }
        }
    }
}
