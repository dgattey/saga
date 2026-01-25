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
  @State private var selection: SidebarSelection? = .home(lastSelectedBookID: nil)
  @StateObject private var navigationHistory = NavigationHistory()
  @State private var scrollContextID = UUID()
  @State private var previousScrollContextID = UUID()
  @StateObject private var scrollStore = ScrollPositionStore()
  @State private var coverMatchActive = false
  @State private var coverMatchTask: Task<Void, Never>?
  @State private var lastSelectionWasHome = true
  @Namespace private var coverNamespace

  var body: some View {
    GoodreadsUploadDropzoneContainer {
      NavigationSplitView(
        sidebar: {
          VStack(alignment: .leading, spacing: 8) {
            HomeSidebarRow(selection: selectionBinding)
            BooksListView(selection: selectionBinding)
          }
        },
        detail: {
          Group {
            switch selection {
            case .book(let selectedBookID):
              if let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book {
                BookContentView(book: selectedBook)
              } else {
                HomeView(selection: selectionBinding)
              }
            default:
              HomeView(selection: selectionBinding)
            }
          }
        }
      )
    }
    .environmentObject(navigationHistory)
    .environmentObject(scrollStore)
    .environment(\.scrollContextID, scrollContextID)
    .environment(\.coverNamespace, coverNamespace)
    .environment(\.coverMatchActive, coverMatchActive)
    .symbolRenderingMode(.hierarchical)
    .toolbar {
      ContentViewToolbar(
        navigationHistory: navigationHistory,
        selection: $selection,
        scrollContextID: $scrollContextID,
        previousScrollContextID: $previousScrollContextID
      )
    }
    #if os(macOS)
      .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    #endif
    .onChange(of: selection) { oldSelection, newSelection in
      let oldEntry = oldSelection.map {
        NavigationEntry(selection: $0, scrollContextID: previousScrollContextID)
      }
      let newEntry = newSelection.map {
        NavigationEntry(selection: $0, scrollContextID: scrollContextID)
      }
      navigationHistory.recordSelectionChange(from: oldEntry, to: newEntry)
      let isHome = newSelection?.isHome ?? true
      if isHome != lastSelectionWasHome {
        startCoverMatch()
      } else {
        coverMatchTask?.cancel()
        coverMatchActive = false
      }
      lastSelectionWasHome = isHome
    }
    .onChange(of: syncViewModel.resetToken) {
      previousScrollContextID = scrollContextID
      scrollContextID = UUID()
      selection = selection?.homeSelectionPreservingLast() ?? .home(lastSelectedBookID: nil)
      scrollStore.reset()
    }
    #if os(macOS)
      .frame(minWidth: 600, minHeight: 300)
    #endif
  }

  private var selectionBinding: Binding<SidebarSelection?> {
    Binding(
      get: { selection },
      set: { newSelection in
        previousScrollContextID = scrollContextID
        guard newSelection != selection else { return }
        scrollContextID = UUID()
        selection = newSelection
      }
    )
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
