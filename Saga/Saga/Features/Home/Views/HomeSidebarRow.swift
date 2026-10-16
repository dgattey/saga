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

  private var isSelected: Bool {
    entry?.selection.isHome == true
  }

  var body: some View {
    Button {
      withAnimation(animationSettings.selectionSpring) {
        guard !isSelected else { return }
        entry = makeHomeEntry()
      }
    } label: {
      HStack(spacing: 8) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.botanicalLeaf.opacity(isSelected ? 0.22 : 0.12))
            .frame(width: 36, height: 36)
          Image(systemName: "books.vertical.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? Color.botanicalLeaf : .secondary)
        }
        .frame(width: 42, height: 36, alignment: .center)

        Text("Home")
          .font(.title3.weight(.semibold))
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selectionBackgroundColor)
          Color.clear
            .glassEffect(
              .regular.tint(selectionBackgroundColor).interactive(),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
      }
    }
    .accessibilityIdentifier(AccessibilityID.Sidebar.homeButton)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
    #if !os(macOS)
      .padding(.top, 8)
    #endif
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      return Color.sidebarSelectionFill(isActiveWindow: controlActiveState != .inactive)
    #else
      return Color.sidebarSelectionFill(isActiveWindow: true)
    #endif
  }
}
