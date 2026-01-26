//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct ContentView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @EnvironmentObject private var syncViewModel: SyncViewModel
  @EnvironmentObject private var animationSettings: AnimationSettings
  @State private var entry: NavigationEntry?
  @StateObject private var navigationHistory: NavigationHistory
  @StateObject private var scrollStore = ScrollPositionStore()
  @StateObject private var bookNavigationViewModel: BookNavigationViewModel
  @State private var detailWidth: CGFloat = 0
  @Namespace private var coverNamespace

  init() {
    let homeContextID = UUID()
    _entry = State(
      initialValue: NavigationEntry(
        selection: .home(lastSelectedBookID: nil),
        scrollContextID: homeContextID
      )
    )
    let history = NavigationHistory(initialHomeScrollContextID: homeContextID)
    _navigationHistory = StateObject(wrappedValue: history)
    _bookNavigationViewModel = StateObject(
      wrappedValue: BookNavigationViewModel(navigationHistory: history))
  }

  var body: some View {
    GoodreadsUploadDropzoneContainer {
      NavigationSplitView(
        sidebar: {
          VStack(alignment: .leading, spacing: 8) {
            HomeSidebarRow(
              entry: $entry,
              makeHomeEntry: {
                navigationHistory.makeHomeEntry(currentEntry: entry, scrollStore: scrollStore)
              }
            )
            BooksListView(entry: $entry)
          }
        },
        detail: {
          Group {
            switch entry?.selection {
            case .book(let selectedBookID):
              if let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book {
                BookContentView(book: selectedBook, detailLayoutWidth: detailWidth)
              } else {
                HomeView(entry: $entry)
              }
            default:
              HomeView(entry: $entry)
            }
          }
          .readSize { size in
            if size.width != detailWidth {
              detailWidth = size.width
            }
          }
        }
      )
    }
    .environmentObject(navigationHistory)
    .environmentObject(scrollStore)
    .environmentObject(bookNavigationViewModel)
    .environment(\.scrollContextID, entry?.scrollContextID)
    .environment(\.coverNamespace, coverNamespace)
    .symbolRenderingMode(.hierarchical)
    .animation(animationSettings.selectionSpring, value: entry?.selection)
    .toolbar {
      ContentViewToolbar(
        navigationHistory: navigationHistory,
        entry: $entry
      )
    }
    #if os(macOS)
      .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    #endif
    .onChange(of: entry) { oldEntry, newEntry in
      navigationHistory.onNavigationChange(from: oldEntry, to: newEntry)
    }
    .onChange(of: syncViewModel.resetToken) {
      scrollStore.reset()
      entry = navigationHistory.makeHomeEntry(
        currentEntry: entry,
        scrollStore: scrollStore,
        cloneFromLast: false
      )
    }
    #if os(macOS)
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        // Scene phase doesn't consistently fire on macOS focus changes, so we sync on app activation.
        Task {
          await syncViewModel.sync()
        }
      }
      .frame(minWidth: 600, minHeight: 300)
    #endif
  }

}
