//
//  AppInformationView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

/// Displays app icon, name, version, and an expandable link on hover.
struct AppInformationView: View {
  @State private var isHoveringAppInfo = false
  @State private var isHoveringLink = false

  var body: some View {
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
    .padding()
    .frame(maxWidth: .infinity)
    .withGlassBackground(edge: .bottom)
    .onHover { hovering in
      withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
        isHoveringAppInfo = hovering
      }
    }
  }

  private var appIcon: PlatformImage? {
    let iconName = Bundle.main.iconFileName
    #if canImport(UIKit)
      let icon = iconName.flatMap { UIImage(named: $0) }
    #elseif canImport(AppKit)
      let icon = iconName.flatMap { NSImage(named: $0) }
    #endif
    return icon
  }
}
