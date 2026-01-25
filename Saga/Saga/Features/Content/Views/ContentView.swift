//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import SwiftUI

struct ContentView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @EnvironmentObject private var syncViewModel: SyncViewModel
  @State private var entry: NavigationEntry?
  @StateObject private var navigationHistory: NavigationHistory
  @StateObject private var scrollStore = ScrollPositionStore()
  @State private var coverMatchActive = false
  @State private var pendingHomeCoverMatch = false
  @State private var pendingHomeScrollContextID: UUID?
  @State private var transitioningFromEntry: NavigationEntry?
  @State private var coverMatchTask: Task<Void, Never>?
  @State private var lastSelectionWasHome = true
  @Namespace private var coverNamespace

  init() {
    let homeContextID = UUID()
    _entry = State(
      initialValue: NavigationEntry(
        selection: .home(lastSelectedBookID: nil),
        scrollContextID: homeContextID
      )
    )
    _navigationHistory = StateObject(
      wrappedValue: NavigationHistory(initialHomeScrollContextID: homeContextID)
    )
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
          ZStack {
            Group {
              switch entry?.selection {
              case .book(let selectedBookID):
                if let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book
                {
                  BookContentView(book: selectedBook)
                } else {
                  HomeView(entry: $entry)
                }
              default:
                HomeView(entry: $entry)
              }
            }
            if let transitioningFromEntry,
              case .book(let previousBookID) = transitioningFromEntry.selection,
              let previousBook = try? viewContext.existingObject(with: previousBookID) as? Book
            {
              BookContentView(book: previousBook)
                .zIndex(1)
            }
          }
        }
      )
    }
    .environmentObject(navigationHistory)
    .environmentObject(scrollStore)
    .environment(\.scrollContextID, entry?.scrollContextID)
    .environment(\.coverNamespace, coverNamespace)
    .environment(\.coverMatchActive, coverMatchActive)
    .symbolRenderingMode(.hierarchical)
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
      navigationHistory.recordSelectionChange(from: oldEntry, to: newEntry)
      let isHome = newEntry?.selection.isHome ?? true
      if isHome != lastSelectionWasHome {
        if isHome {
          transitioningFromEntry = oldEntry
          pendingHomeCoverMatch = true
          pendingHomeScrollContextID = newEntry?.scrollContextID
        } else {
          pendingHomeCoverMatch = false
          pendingHomeScrollContextID = nil
          transitioningFromEntry = nil
          startCoverMatch()
        }
      } else {
        coverMatchTask?.cancel()
        coverMatchActive = false
      }
      lastSelectionWasHome = isHome
    }
    .onReceive(NotificationCenter.default.publisher(for: .homeScrollRestored)) { notification in
      guard pendingHomeCoverMatch else { return }
      guard let contextID = notification.object as? UUID else { return }
      guard contextID == pendingHomeScrollContextID else { return }
      pendingHomeCoverMatch = false
      pendingHomeScrollContextID = nil
      startCoverMatch()
      withAnimation(AppAnimation.selectionSpring) {
        transitioningFromEntry = nil
      }
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
      .frame(minWidth: 600, minHeight: 300)
    #endif
  }

  private func startCoverMatch() {
    coverMatchTask?.cancel()
    coverMatchActive = true
    coverMatchTask = Task { @MainActor in
      let delay = UInt64(AppAnimation.coverMatchHoldDuration * 1_000_000_000)
      try? await Task.sleep(nanoseconds: delay)
      if !Task.isCancelled {
        coverMatchActive = false
      }
    }
  }
}
