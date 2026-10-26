//
//  HomeView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import CoreData
import SwiftUI

private struct Constants {
  static let headerPaddingY: CGFloat = 16
}

struct HomeView: View {
  @Environment(BooksViewModel.self) private var viewModel
  @Environment(\.scrollContextID) private var scrollContextID
  @AppStorage(HomeBookSort.storageKey) private var storedSort: HomeBookSort = .defaultOrder
  @Binding var entry: NavigationEntry?
  private let sortOverride: Binding<HomeBookSort>?

  init(entry: Binding<NavigationEntry?>, sort: Binding<HomeBookSort>? = nil) {
    self._entry = entry
    self.sortOverride = sort
  }

  private var sortBinding: Binding<HomeBookSort> {
    sortOverride ?? $storedSort
  }

  private var activeSort: HomeBookSort {
    sortBinding.wrappedValue
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
        ForEach(sections) { section in
          Section {
            section.content
          } header: {
            headerTitleView(title: section.title)
          }
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

  private var sections: [HomeSection] {
    [
      HomeSection(
        id: "books",
        title: "Books",
        content: AnyView(
          HomeBooksSectionView(entry: $entry, sort: activeSort)
        )
      )
    ]
  }

  private func headerTitleView(title: String) -> some View {
    HomeBooksHeaderView(
      title: title,
      bookCountText: viewModel.bookCountText,
      sort: sortBinding
    )
  }
}

struct HomeBooksHeaderView: View {
  let title: String
  let bookCountText: String
  @Binding var sort: HomeBookSort

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .font(.largeTitleBold)
        Text(bookCountText)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .accessibilityIdentifier(AccessibilityID.Home.bookCount)
      }

      Spacer(minLength: 8)

      Menu {
        Picker("Sort By", selection: $sort) {
          ForEach(HomeBookSort.allCases) { option in
            Label(option.title, systemImage: option.systemImage)
              .tag(option)
          }
        }
        .pickerStyle(.inline)
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "arrow.up.arrow.down")
            .font(.caption.weight(.semibold))
          Text(sort.title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
        }
        .foregroundStyle(sort == .defaultOrder ? Color.secondary : Color.botanicalLeaf)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          Capsule(style: .continuous)
            .fill(
              sort == .defaultOrder
                ? Color.primary.opacity(0.06)
                : Color.botanicalLeaf.opacity(0.14)
            )
        )
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .accessibilityLabel("Sort books, \(sort.title)")
      .accessibilityIdentifier(AccessibilityID.Home.sortMenu)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 32)
    .padding(.vertical, Constants.headerPaddingY)
  }
}
