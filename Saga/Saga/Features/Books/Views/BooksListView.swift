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
          .padding(.bottom, 4)
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
    #if os(iOS)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let activeBook = currentlyReadingBook {
          NowReadingFloatingCardView(
            book: activeBook,
            onSelect: {
              selectBook(activeBook.objectID)
            }
          )
          .padding(.horizontal, 12)
          .padding(.top, 8)
          .padding(.bottom, 22)
        }
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
    #endif
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

#if os(iOS)
  private struct NowReadingFloatingCardView: View {
    @ObservedObject var book: Book
    let onSelect: () -> Void

    private let cornerRadius: CGFloat = 14

    var body: some View {
      Button(action: onSelect) {
        HStack(spacing: 12) {
          BookCoverImageView(book: book, targetSize: CGSize(width: 36, height: 52))
            .frame(width: 36, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.32), radius: 6, y: 3)

          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
              Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(Color.botanicalSage)
              Text("Currently reading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.botanicalSage)
            }
            Text(book.title ?? book.id)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if let author = book.author {
              Text(author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }

          Spacer(minLength: 8)

          Image(systemName: "chevron.right")
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color.botanicalSage)
            .frame(width: 28, height: 28)
            .glassEffect(
              .regular.tint(Color.botanicalLeaf.opacity(0.24)),
              in: Circle()
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      }
      .buttonStyle(.plain)
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
              LinearGradient(
                colors: [
                  Color.botanicalForest.opacity(0.88),
                  Color.botanicalSurfaceTint.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          Color.clear
            .glassEffect(
              .regular.tint(Color.botanicalLeaf.opacity(0.36)).interactive(),
              in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: [
                Color.white.opacity(0.62),
                Color.botanicalSage.opacity(0.55),
                Color.white.opacity(0.22),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1.5
          )
      }
      .compositingGroup()
      .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
  }
#endif

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
