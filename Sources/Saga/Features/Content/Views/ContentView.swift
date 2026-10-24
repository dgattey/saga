//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import DylCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct ContentView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(SyncViewModel.self) private var syncViewModel
  @Environment(CachesViewModel.self) private var cachesViewModel
  @Environment(AnimationSettings.self) private var animationSettings
  #if os(macOS)
    @Environment(\.openWindow) private var openWindow
  #endif
  @State private var entry: NavigationEntry?
  @State private var isShowingSettings = LaunchOverrides.current.sagaInitialView == .settings
  @State private var isCreatingBook = false
  @State private var navigationHistory: NavigationHistory
  @State private var scrollStore = ScrollPositionStore()
  @State private var bookNavigationViewModel: BookNavigationViewModel
  @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
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
    _navigationHistory = State(initialValue: history)
    _bookNavigationViewModel = State(
      initialValue: BookNavigationViewModel(navigationHistory: history))
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
          BooksListView(entry: $entry, onNewBook: { isCreatingBook = true })
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        .botanicalPageBackground()
      },
      detail: {
        Group {
          switch entry?.selection {
          case .book(let selectedBookID):
            if let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book {
              BookContentView(book: selectedBook, onDelete: navigateHome)
            } else {
              HomeView(entry: $entry)
            }
          default:
            HomeView(entry: $entry)
          }
        }
        .botanicalPageBackground()
      }
    )
    .overlay {
      BookSearchSpotlightView(entry: $entry)
    }
    .environment(navigationHistory)
    .environment(scrollStore)
    .environment(bookNavigationViewModel)
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
        .presentationDragIndicator(.visible)
        .environment(syncViewModel)
        .environment(cachesViewModel)
        .environment(animationSettings)
      }
    #endif
    .focusedSceneValue(\.isCreatingBook, $isCreatingBook)
    .sheet(isPresented: $isCreatingBook) {
      BookEditorView(book: nil, context: viewContext) { outcome in
        isCreatingBook = false
        if case .saved(let bookID) = outcome {
          entry = NavigationEntry(selection: .book(bookID))
        }
      }
      .botanicalPageBackground()
      .environment(animationSettings)
      #if os(macOS)
        .frame(minWidth: 840, idealWidth: 848, minHeight: 620, idealHeight: 640)
      #endif
    }
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
      guard LaunchOverrides.current.sagaInitialView == nil else { return }
      await syncViewModel.syncWithContentful()
    }
    #if os(macOS)
      .onAppear {
        if LaunchOverrides.current.sagaInitialView == .settings {
          openWindow(id: "settings")
        }
      }
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

  private func navigateHome() {
    entry = navigationHistory.makeHomeEntry(currentEntry: entry, scrollStore: scrollStore)
  }
}
