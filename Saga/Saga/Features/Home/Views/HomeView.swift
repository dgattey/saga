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

/// Renders the home view with a book grid
struct HomeView: View {
  @EnvironmentObject private var viewModel: BooksViewModel
  @Environment(\.scrollContextID) private var scrollContextID
  @Binding var entry: NavigationEntry?

  var body: some View {
    ZStack(alignment: .topLeading) {
      PersistentScrollView(
        scrollKey: ScrollKey(
          scope: .home,
          region: "main",
          contextID: scrollContextID
        ),
        onRestore: notifyScrollRestored
      ) {
        ScrollVelocityReader()
        LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
          ForEach(sections) { section in
            Section {
              section.content
            } header: {
              headerPlaceholderView(title: section.title)
            }
          }
        }
      }
      .scrollVelocityThrottle()
      .withGlassOverlay(.top)
      .accessibilityIdentifier(AccessibilityID.Home.scroll)
      headerTitleView(title: sections.first?.title ?? "")
        .zIndex(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle("Home")
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
          HomeBooksSectionView(entry: $entry)
        )
      )
    ]
  }

  private func headerPlaceholderView(title: String) -> some View {
    Text(title)
      .font(.largeTitleBold)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, Constants.headerPaddingY)
      .opacity(0)
      .allowsHitTesting(false)
  }

  private func headerTitleView(title: String) -> some View {
    Text(title)
      .font(.largeTitleBold)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, Constants.headerPaddingY)
      .allowsHitTesting(false)
  }
}
