//
//  HomeView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import CoreData
import DylCore
import SwiftUI

private struct Constants {
  static let headerPaddingY: CGFloat = 16
}

struct HomeView: View {
  @Environment(BooksViewModel.self) private var viewModel
  @Environment(\.scrollContextID) private var scrollContextID
  @AppStorage(HomeBookSort.storageKey) private var storedSort: HomeBookSort = .defaultOrder
  @Binding var entry: NavigationEntry?

  private var activeSort: HomeBookSort {
    LaunchOverrides.current.homeSort ?? storedSort
  }

  var body: some View {
    PersistentScrollView(
      scrollKey: ScrollKey(
        scope: .home,
        region: "main",
        contextID: scrollContextID
      ),
      onRestore: notifyScrollRestored
    ) {
      LazyVStack(alignment: .leading) {
        Section {
          HomeBooksSectionView(entry: $entry, sort: activeSort)
        } header: {
          headerTitleView
        }
      }
    }
    .scrollVelocityThrottle()
    .scrollEdgeEffectStyle(.soft, for: .top)
    .accessibilityIdentifier(AccessibilityID.Home.scroll)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle("Home")
    .botanicalPageBackground()
    .accessibilityIdentifier(AccessibilityID.Home.view)
    .accessibilityElement(children: .contain)
    #if os(macOS)
      .toolbar(removing: .title)
    #endif
  }

  private func notifyScrollRestored() {
    guard let scrollContextID else { return }
    NotificationCenter.default.post(
      name: .homeScrollRestored,
      object: scrollContextID
    )
  }

  private var headerTitleView: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("Books")
        .font(.largeTitleBold)
      Text(viewModel.bookCountText)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityIdentifier(AccessibilityID.Home.bookCount)
      Spacer()
      Menu {
        Picker("Sort By", selection: $storedSort) {
          ForEach(HomeBookSort.allCases) { option in
            Label(option.title, systemImage: option.systemImage).tag(option)
          }
        }
        .pickerStyle(.inline)
      } label: {
        Label(activeSort.title, systemImage: "arrow.up.arrow.down")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(activeSort == .defaultOrder ? Color.secondary : Color.botanicalLeaf)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            Capsule(style: .continuous)
              .fill(
                activeSort == .defaultOrder
                  ? Color.primary.opacity(0.06)
                  : Color.botanicalLeaf.opacity(0.14)
              )
          )
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityIdentifier(AccessibilityID.Home.sortMenu)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 32)
    .padding(.vertical, Constants.headerPaddingY)
  }
}
