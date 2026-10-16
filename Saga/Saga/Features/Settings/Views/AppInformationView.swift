//
//  AppInformationView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import SwiftUI

struct AppInformationView: View {
  @State private var isHoveringAppInfo = false

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 16) {
        appIconView
          .scaleEffect(isHoveringAppInfo ? 1.06 : 1.0)

        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Saga")
              .font(.title2.weight(.bold))
            Text("v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.botanicalLeaf.opacity(0.10), in: Capsule())
              .overlay(
                Capsule()
                  .strokeBorder(Color.botanicalLeaf.opacity(0.22), lineWidth: 1)
              )
          }

          Text("Personal library & reading tracker for macOS and iOS")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          Text("Crafted by Dylan Gattey")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }

        Spacer(minLength: 0)
      }

      Divider()
        .opacity(0.6)

      quickLinksRow
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onHover { hovering in
      withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
        isHoveringAppInfo = hovering
      }
    }
  }

  private var quickLinksRow: some View {
    HStack(spacing: 8) {
      ForEach(QuickLinkItem.all) { item in
        Link(destination: item.url) {
          Label(item.title, systemImage: item.systemImage)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.glass)
        #if os(macOS)
          .pointerStyle(.link)
        #endif
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var appIconView: some View {
    if let appIcon {
      Image(platformImage: appIcon)
        .resizable()
        .interpolation(.high)
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color.botanicalLeaf, Color.botanicalForest],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        Image(systemName: "books.vertical.fill")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 60, height: 60)
      .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    }
  }

  private var appIcon: PlatformImage? {
    let iconName = Bundle.main.iconFileName
    #if canImport(UIKit)
      if let icon = iconName.flatMap({ UIImage(named: $0) }) ?? UIImage(named: "AppIcon") {
        return icon
      }
      return nil
    #elseif canImport(AppKit)
      if let icon = iconName.flatMap({ NSImage(named: $0) }) ?? NSImage(named: "AppIcon") {
        return icon
      }
      return nil
    #endif
  }
}
