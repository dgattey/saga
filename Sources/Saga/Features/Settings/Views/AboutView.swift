//
//  AboutView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import DylCore
import SwiftUI

/// Standalone About pane: app identity hero plus website, source, and author links.
struct AboutView: View {
  var body: some View {
    Group {
      Section {
        VStack(spacing: 6) {
          appIconView
            .padding(.bottom, 6)
          Text("Saga")
            .font(.title2.weight(.bold))
          Text("Version \(AppInfo.main.version ?? "–") (\(AppInfo.main.build ?? "–"))")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
          Text("Personal library & reading tracker for macOS and iOS")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Text("Crafted by Dylan Gattey")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }

      Section("Links") {
        ForEach(QuickLinkItem.all) { item in
          LabeledContent {
            Link(destination: item.url) {
              Text(item.url.host() ?? item.url.absoluteString)
            }
            #if os(macOS)
              .pointerStyle(.link)
            #endif
          } label: {
            Label(item.title, systemImage: item.systemImage)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var appIconView: some View {
    if let appIcon {
      Image(platformImage: appIcon)
        .resizable()
        .interpolation(.high)
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    } else {
      Image(systemName: "books.vertical.fill")
        .font(.system(size: 32, weight: .semibold))
        .foregroundStyle(Color.botanicalCream)
        .frame(width: 72, height: 72)
        .background(Color.botanicalOlive, in: .rect(cornerRadius: 16, style: .continuous))
    }
  }

  private var appIcon: PlatformImage? {
    let iconName = Bundle.main.iconFileName
    #if canImport(UIKit)
      return iconName.flatMap({ UIImage(named: $0) }) ?? UIImage(named: "AppIcon")
    #elseif canImport(AppKit)
      return iconName.flatMap({ NSImage(named: $0) }) ?? NSImage(named: "AppIcon")
    #endif
  }
}
