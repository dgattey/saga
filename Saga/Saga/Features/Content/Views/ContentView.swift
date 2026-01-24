//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var syncViewModel: SyncViewModel
    @State private var selection: SidebarSelection? = .home(lastSelectedBookID: nil)
    @StateObject private var navigationHistory = NavigationHistory()
    @State private var coverMatchActive = false
    @State private var coverMatchTask: Task<Void, Never>?
    @State private var lastSelectionWasHome = true
    @Namespace private var coverNamespace

    var body: some View {
        GoodreadsUploadDropzoneContainer {
            NavigationSplitView(sidebar: {
                VStack(alignment: .leading, spacing: 8) {
                    HomeSidebarRow(selection: $selection)
                    BooksListView(selection: $selection)
                }
            }, detail: {
                Group {
                    switch selection {
                    case .book(let selectedBookID):
                        if let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book {
                            BookContentView(book: selectedBook)
                        } else {
                            HomeView(selection: $selection)
                        }
                    default:
                        HomeView(selection: $selection)
                    }
                }
            })
        }
        .environmentObject(navigationHistory)
        .environment(\.coverNamespace, coverNamespace)
        .environment(\.coverMatchActive, coverMatchActive)
        .symbolRenderingMode(.hierarchical)
        .toolbar {
            ContentViewToolbar(navigationHistory: navigationHistory, selection: $selection)
        }
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .onChange(of: selection) { oldSelection, newSelection in
            navigationHistory.recordSelectionChange(from: oldSelection, to: newSelection)
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
            selection = selection?.homeSelectionPreservingLast() ?? .home(lastSelectedBookID: nil)
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
