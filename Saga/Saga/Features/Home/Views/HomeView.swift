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
  @EnvironmentObject private var viewModel: BooksViewModel
  @Environment(\.scrollContextID) private var scrollContextID
  @Binding var entry: NavigationEntry?

  var body: some View {
    PersistentScrollView(
      scrollKey: ScrollKey(
        scope: .home,
        region: "main",
        contextID: scrollContextID
      ),
      onRestore: notifyScrollRestored
    ) {
      ScrollVelocityReader()
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
          HomeBooksSectionView(entry: $entry)
        )
      )
    ]
  }

  private func headerTitleView(title: String) -> some View {
    Text(title)
      .font(.largeTitleBold)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, Constants.headerPaddingY)
  }
}
