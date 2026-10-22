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
  @Environment(BooksViewModel.self) private var viewModel
  @Environment(AnimationSettings.self) private var animationSettings
  #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
  #endif
  @Binding var entry: NavigationEntry?
  var onNewBook: () -> Void = {}
  @FetchRequest(
    fetchRequest: Book.sidebarFetchRequest(),
    animation: .default
  ) private var books: FetchedResults<Book>

  /// Focus state to ensure keyboard events are received
  @FocusState private var isListFocused: Bool
  @FocusState private var isSearchFocused: Bool

  /// Throttle keyboard navigation to allow animations to complete
  @State private var navThrottle = NavigationThrottle()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      BookListHeaderView(onNewBook: onNewBook)

      ScrollViewReader { proxy in
        PersistentScrollView(scrollKey: ScrollKey(scope: .sidebarBooks, region: "list")) {
          LazyVStack(alignment: .leading, spacing: 4) {
            if viewModel.filteredBooks.isEmpty, viewModel.hasActiveSearch {
              BookListEmptyStateView()
            } else {
              ForEach(viewModel.filteredBooks, id: \.book.objectID) { result in
                BookListRowView(
                  result: result,
                  isSelected: entry?.selection == .book(result.book.objectID),
                  selectionBackgroundColor: selectionBackgroundColor,
                  onSelect: {
                    selectBook(result.book.objectID)
                  },
                  onDelete: {
                    deleteBook(result.book)
                  }
                )
                .id(result.book.objectID)
                .accessibilityIdentifier(AccessibilityID.Books.bookRow(result.index))
              }
            }
          }
          .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if !isSearchActive, let activeBook = currentlyReadingBook {
            NowReadingBarView(
              book: activeBook,
              onSelect: {
                selectBook(activeBook.objectID)
              }
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            #if os(iOS)
              .padding(.bottom, 8)
            #else
              .padding(.bottom, 12)
            #endif
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
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
        .task(id: viewModel.filteredBooks.count) {
          guard LaunchOptions.scrollSidebarToBottom,
            let lastBookID = viewModel.filteredBooks.last?.book.objectID
          else { return }
          try? await Task.sleep(for: .milliseconds(300))
          withAnimation(.none) {
            proxy.scrollTo(lastBookID, anchor: .center)
          }
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
    .animation(animationSettings.selectionSpring, value: isSearchActive)
    #if os(macOS)
      .frame(minWidth: 200, idealWidth: 300)
    #endif
    .task(id: viewModel.searchModel.key) {
      viewModel.performSearch(
        with: books,
        debounce: viewModel.searchModel.query.isEmpty ? nil : .milliseconds(200)
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
    .task(id: books.count) {
      guard let initialView = LaunchOptions.initialView, !books.isEmpty else { return }
      LoggerService.log(
        "Initial view \(initialView.rawValue) with \(books.count) books", surface: .launch)
      switch initialView {
      case .home, .settings:
        break
      case .book, .bookEdit:
        guard let targetBook = currentlyReadingBook ?? books.first else { return }
        selectBook(targetBook.objectID)
        LoggerService.log("Opened book \(targetBook.title ?? "")", surface: .launch)
      case .search:
        viewModel.searchModel.tokens = [.hasNotes]
        if let query = LaunchOptions.searchQuery, !query.isEmpty {
          viewModel.searchModel.searchText = query
        }
        viewModel.performSearch(with: books, debounce: nil)
      }
    }
    .searchable(
      text: Bindable(viewModel).searchModel.searchText,
      tokens: Bindable(viewModel).searchModel.tokens,
      suggestedTokens: .constant(viewModel.searchModel.suggestedTokens),
      placement: .sidebar
    ) { token in
      Label(token.label, systemImage: token.systemImage)
    }
    .searchFocused($isSearchFocused)
    .onReceive(viewModel.sidebarSearchFocusRequests) { _ in
      isSearchFocused = true
    }
    .navigationTitle("All books")
  }

  private var currentlyReadingBook: Book? {
    books.first(where: { $0.readingStatus == .reading })
  }

  private var isSearchActive: Bool {
    viewModel.hasActiveSearch || isSearchFocused
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

  private func scrollToSelection(
    selection: SidebarSelection?,
    proxy: ScrollViewProxy
  ) {
    guard case .book(let selectedID) = selection else { return }
    guard viewModel.filteredBooks.contains(where: { $0.book.objectID == selectedID }) else {
      return
    }
    // Use a fast animation that completes quickly for smooth rapid navigation
    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
      proxy.scrollTo(selectedID, anchor: .center)
    }
  }

  // MARK: - Book Management

  private func deleteBook(_ book: Book) {
    let service = BookMutationService(context: viewContext)
    let bookID = book.objectID
    Task {
      do {
        let entryID = try await service.delete(bookID)
        await service.syncDeletion(id: entryID)
      } catch {
        LoggerService.log("Failed to delete book", error: error, surface: .persistence)
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
  var onNewBook: () -> Void = {}

  var body: some View {
    HStack {
      Text("Books")
        .font(.headline)
        .foregroundStyle(.secondary)
      Spacer()
      Button(action: onNewBook) {
        Image(systemName: "plus")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.botanicalLeaf)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .help("New Book (⌘N)")
      .accessibilityLabel("New Book")
      .accessibilityIdentifier(AccessibilityID.Books.newBookButton)
    }
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
  let result: BookSearchResult
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(selectionBackgroundColor)
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
private final class NavigationThrottle {
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
