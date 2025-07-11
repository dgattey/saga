//
//  SettingsView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SyncViewModel
    
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
            Task {
                await viewModel.resetAndSync()
            }
        }) {
            HStack(spacing: 8) {
                if viewModel.isSyncing {
                    ProgressView()
                        .progressViewStyle(.automatic)
                        .controlSize(.small)
                    Text("Resetting...")
                } else {
                    Text("Reset all local data")
                }
            }
        }
        .disabled(viewModel.isSyncing)
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
