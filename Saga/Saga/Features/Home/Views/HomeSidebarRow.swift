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
        Image(systemName: "books.vertical")
          .font(.headline)
          .imageScale(.medium)
          .foregroundStyle(isSelected ? Color.botanicalLeaf : .secondary)
        Text("Home")
          .font(.headline)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        Color.clear
          .glassEffect(
            .regular.tint(selectionBackgroundColor).interactive(),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
      }
    }
    .accessibilityIdentifier(AccessibilityID.Sidebar.homeButton)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
    .padding(.top, 8)
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      return Color.sidebarSelectionFill(isActiveWindow: controlActiveState != .inactive)
    #else
      return Color.sidebarSelectionFill(isActiveWindow: true)
    #endif
  }
}
