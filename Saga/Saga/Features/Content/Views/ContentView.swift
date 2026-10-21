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
  @EnvironmentObject private var cachesViewModel: CachesViewModel
  @EnvironmentObject private var animationSettings: AnimationSettings
  @State private var entry: NavigationEntry?
  @State private var isShowingSettings = false
  @StateObject private var navigationHistory: NavigationHistory
  @StateObject private var scrollStore = ScrollPositionStore()
  @StateObject private var bookNavigationViewModel: BookNavigationViewModel
  @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
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
    NavigationSplitView(
      preferredCompactColumn: $preferredCompactColumn,
      sidebar: {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            HomeSidebarRow(
              entry: $entry,
              makeHomeEntry: {
                navigationHistory.makeHomeEntry(currentEntry: entry, scrollStore: scrollStore)
              }
            )
            #if !os(macOS)
              Button {
                isShowingSettings = true
              } label: {
                Image(systemName: "gearshape")
                  .font(.headline)
                  .foregroundStyle(Color.botanicalLeaf)
                  .frame(width: 32, height: 32)
                  .glassEffect(.regular.interactive(), in: Circle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Settings")
              .padding(.trailing, SidebarLayout.rowHorizontalPadding)
              .padding(.top, 8)
            #endif
          }
          BooksListView(entry: $entry)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        .botanicalPageBackground()
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
        .botanicalPageBackground()
        .readSize { size in
          if size.width != detailWidth {
            detailWidth = size.width
          }
        }
      }
    )
    .overlay {
      BookSearchSpotlightView(entry: $entry)
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
        entry: $entry,
        isShowingSettings: $isShowingSettings
      )
    }
    #if os(macOS)
      .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    #else
      .sheet(isPresented: $isShowingSettings) {
        SettingsView()
        .environmentObject(syncViewModel)
        .environmentObject(cachesViewModel)
        .environmentObject(animationSettings)
      }
    #endif
    .onChange(of: entry) { oldEntry, newEntry in
      navigationHistory.onNavigationChange(from: oldEntry, to: newEntry)
      if newEntry != nil {
        preferredCompactColumn = .detail
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
    .task {
      await syncViewModel.syncWithContentful()
    }
    #if os(macOS)
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        // Scene phase doesn't consistently fire on macOS focus changes, so we sync on app activation.
        Task {
          await syncViewModel.syncWithContentful()
        }
      }
      .frame(minWidth: 600, minHeight: 300)
    #endif
  }

}
