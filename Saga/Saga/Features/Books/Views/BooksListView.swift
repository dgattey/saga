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
    sortDescriptors: [NSSortDescriptor(keyPath: \Book.readDateStarted, ascending: false)],
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
              ForEach(Array(viewModel.filteredBooks.enumerated()), id: \.element.model.objectID) {
                index, result in
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
                .accessibilityIdentifier(AccessibilityID.Books.bookRow(index))
              }
            }
          }
          .padding(.vertical, 4)
        }
        .scrollVelocityThrottle()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .accessibilityIdentifier(AccessibilityID.Books.sidebarScrollArea)
        .onChange(of: entry?.selection) { _, newSelection in
          scrollToSelection(selection: newSelection, proxy: proxy)
        }
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
    .onChange(of: Array(books)) {
      viewModel.performSearch(with: books, debounce: .milliseconds(150))
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

  /// Selects a book via keyboard navigation, preserving scroll context and using fast animation
  private func selectBookViaKeyboard(_ bookID: NSManagedObjectID) {
    guard entry?.selection != .book(bookID) else { return }
    // Preserve the existing scrollContextID to avoid environment changes that cause re-renders
    let scrollContextID = entry?.scrollContextID ?? UUID()
    // Use a fast animation for keyboard navigation
    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
      entry = NavigationEntry(selection: .book(bookID), scrollContextID: scrollContextID)
    }
    // Scrolling is handled by onChange(of: entry?.selection)
  }

  // MARK: - Keyboard Navigation

  private func navigateToNextBook() -> KeyPress.Result {
    let filteredBooks = viewModel.filteredBooks
    guard !filteredBooks.isEmpty else { return .ignored }

    let nextBookID: NSManagedObjectID

    switch entry?.selection {
    case .home:
      // From home, go to first book
      nextBookID = filteredBooks[0].model.objectID

    case .book(let currentID):
      // Find current index and go to next
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.model.objectID == currentID })
      else {
        // Current book not in filtered list, go to first
        nextBookID = filteredBooks[0].model.objectID
        break
      }
      let nextIndex = currentIndex + 1
      guard nextIndex < filteredBooks.count else {
        // Already at last book
        return .handled
      }
      nextBookID = filteredBooks[nextIndex].model.objectID

    case nil:
      nextBookID = filteredBooks[0].model.objectID
    }

    selectBookViaKeyboard(nextBookID)
    return .handled
  }

  private func navigateToPreviousBook() -> KeyPress.Result {
    let filteredBooks = viewModel.filteredBooks
    guard !filteredBooks.isEmpty else { return .ignored }

    switch entry?.selection {
    case .home, nil:
      // Already at home or no selection, can't go further up
      return .ignored

    case .book(let currentID):
      guard let currentIndex = filteredBooks.firstIndex(where: { $0.model.objectID == currentID })
      else {
        // Current book not in filtered list, stay put
        return .ignored
      }

      if currentIndex == 0 {
        // At first book, go to home - preserve scroll context
        let homeSelection =
          entry?.selection.homeSelectionPreservingLast()
          ?? .home(lastSelectedBookID: currentID)
        let scrollContextID = entry?.scrollContextID ?? UUID()
        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
          entry = NavigationEntry(selection: homeSelection, scrollContextID: scrollContextID)
        }
        return .handled
      }

      let previousIndex = currentIndex - 1
      let previousBookID = filteredBooks[previousIndex].model.objectID
      selectBookViaKeyboard(previousBookID)
      return .handled
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
      switch controlActiveState {
      case .inactive:
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
      default:
        return Color(nsColor: .selectedContentBackgroundColor)
      }
    #else
      // iOS fallback: use standard selection-like background
      return Color.accentColor.opacity(0.15)
    #endif
  }
}

private struct BookListHeaderView: View {
  var body: some View {
    Text("Books")
      .font(.headline)
      .foregroundStyle(.secondary)
      .padding(.leading, SidebarLayout.headerLeadingPadding)
      .padding(.trailing, SidebarLayout.rowHorizontalPadding)
  }
}

private struct BookListEmptyStateView: View {
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
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 6)
              .fill(selectionBackgroundColor)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
