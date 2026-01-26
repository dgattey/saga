//
//  HomeSidebarRow.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct HomeSidebarRow: View {
  #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
  #endif
  @EnvironmentObject private var animationSettings: AnimationSettings
  @Binding var entry: NavigationEntry?
  let makeHomeEntry: () -> NavigationEntry

  var body: some View {
    Button {
      withAnimation(animationSettings.selectionSpring) {
        guard entry?.selection.isHome != true else { return }
        entry = makeHomeEntry()
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "house")
          .font(.headline)
          .imageScale(.medium)
        Text("Home")
          .font(.headline)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
      .background {
        if entry?.selection.isHome == true {
          RoundedRectangle(cornerRadius: 6)
            .fill(selectionBackgroundColor)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
    .padding(.top, 8)
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      switch controlActiveState {
      case .inactive:
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
      default:
        return Color(nsColor: .selectedContentBackgroundColor)
      }
    #else
      // iOS fallback: use standard selection-like background
      return Color.accentColor.opacity(0.15)
    #endif
  }
}
