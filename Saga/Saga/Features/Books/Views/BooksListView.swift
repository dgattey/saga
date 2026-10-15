//
//  BooksListView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import CoreData
import SwiftUI

struct BooksListView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @EnvironmentObject private var viewModel: BooksViewModel
  @EnvironmentObject private var animationSettings: AnimationSettings
  #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
  #endif
  @Binding var entry: NavigationEntry?
  @FetchRequest(
    fetchRequest: Book.sidebarFetchRequest(),
    animation: .default
  ) private var books: FetchedResults<Book>

  /// Focus state to ensure keyboard events are received
  @FocusState private var isListFocused: Bool

  /// Throttle keyboard navigation to allow animations to complete
  @StateObject private var navThrottle = NavigationThrottle()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      BookListHeaderView()

      ScrollViewReader { proxy in
        PersistentScrollView(scrollKey: ScrollKey(scope: .sidebarBooks, region: "list")) {
          ScrollVelocityReader()
          LazyVStack(alignment: .leading, spacing: 4) {
            if viewModel.filteredBooks.isEmpty, hasActiveSearch {
              BookListEmptyStateView()
            } else {
              ForEach(viewModel.filteredBooks, id: \.model.objectID) { result in
                BookListRowView(
                  result: result,
                  isSelected: entry?.selection == .book(result.model.objectID),
                  selectionBackgroundColor: selectionBackgroundColor,
                  onSelect: {
                    selectBook(result.model.objectID)
                  },
                  onDelete: {
                    deleteBook(result.model)
                  }
                )
                .id(result.model.objectID)
                .accessibilityIdentifier(AccessibilityID.Books.bookRow(result.index))
              }
            }
          }
          .padding(.vertical, 4)
        }
        .scrollVelocityThrottle()
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier(AccessibilityID.Books.sidebarScrollArea)
        .onChange(of: entry?.selection) { _, newSelection in
          scrollToSelection(selection: newSelection, proxy: proxy)
        }
        #if os(macOS)
          .onMoveCommand { direction in
            guard navThrottle.canNavigate() else { return }

            switch direction {
            case .down:
              _ = navigateToNextBook()
            case .up:
              _ = navigateToPreviousBook()
            default:
              break
            }
          }
        #endif
      }
    }
    #if os(macOS)
      .frame(minWidth: 200, idealWidth: 300)
    #endif
    .task(id: viewModel.searchModel.searchText) {
      viewModel.performSearch(
        with: books,
        debounce: viewModel.searchModel.searchText.isEmpty ? nil : .milliseconds(200)
      )
    }
    .onChange(of: books.count) {
      viewModel.handleBooksChange(books)
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .NSManagedObjectContextObjectsDidChange,
        object: viewContext
      )
    ) { notification in
      viewModel.handleBooksChangeNotification(notification, books: books)
    }
    .searchable(
      text: $viewModel.searchModel.searchText,
      placement: .sidebar
    )
    .navigationTitle("All books")
  }

  // MARK: - Selection

  private func selectBook(_ bookID: NSManagedObjectID) {
    guard entry?.selection != .book(bookID) else { return }
    withAnimation(animationSettings.selectionSpring) {
      entry = NavigationEntry(selection: .book(bookID))
    }
  }

  // MARK: - Keyboard Navigation

  private func navigateToNextBook() -> KeyPress.Result {
    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
      viewModel.navigateToNextBook(entry: &entry)
    }
  }

  private func navigateToPreviousBook() -> KeyPress.Result {
    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
      viewModel.navigateToPreviousBook(entry: &entry)
    }
  }

  // MARK: - Scroll Management

  private var hasActiveSearch: Bool {
    !viewModel.searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func scrollToSelection(
    selection: SidebarSelection?,
    proxy: ScrollViewProxy
  ) {
    guard case .book(let selectedID) = selection else { return }
    guard viewModel.filteredBooks.contains(where: { $0.model.objectID == selectedID }) else {
      return
    }
    // Use a fast animation that completes quickly for smooth rapid navigation
    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
      proxy.scrollTo(selectedID, anchor: .center)
    }
  }

  // MARK: - Book Management

  private func deleteBook(_ book: Book) {
    withAnimation {
      viewContext.delete(book)
      do {
        try viewContext.save()
      } catch {
        let nsError = error as NSError
        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
      }
    }
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      return Color.sidebarSelectionFill(isActiveWindow: controlActiveState != .inactive)
    #else
      return Color.sidebarSelectionFill(isActiveWindow: true)
    #endif
  }
}

struct BookListHeaderView: View {
  var body: some View {
    Text("Books")
      .font(.headline)
      .foregroundStyle(.secondary)
      .padding(.leading, SidebarLayout.headerLeadingPadding)
      .padding(.trailing, SidebarLayout.rowHorizontalPadding)
  }
}

struct BookListEmptyStateView: View {
  var body: some View {
    Text("No results")
      .foregroundStyle(.secondary)
      .padding(.vertical, 8)
      .padding(.trailing, SidebarLayout.rowHorizontalPadding)
      .padding(.leading, SidebarLayout.rowHorizontalPadding + 8)
  }
}

private struct BookListRowView: View {
  let result: SearchHighlightResult<Book>
  let isSelected: Bool
  let selectionBackgroundColor: Color
  let onSelect: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button(action: onSelect) {
      BookListPreviewView(result: result)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        Color.clear
          .glassEffect(
            .regular.tint(selectionBackgroundColor).interactive(),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
      }
    }
    .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
    .contextMenu {
      Button("Delete", action: onDelete)
    }
  }
}

// MARK: - Navigation Throttle

/// Throttles rapid keyboard navigation to allow animations to complete
private final class NavigationThrottle: ObservableObject {
  /// Interval between allowed navigations
  private let interval: TimeInterval = 0.32
  private var lastNavTime: Date = .distantPast

  /// Returns true if enough time has passed to allow navigation
  func canNavigate() -> Bool {
    let now = Date()
    guard now.timeIntervalSince(lastNavTime) >= interval else {
      return false
    }
    lastNavTime = now
    return true
  }
}
