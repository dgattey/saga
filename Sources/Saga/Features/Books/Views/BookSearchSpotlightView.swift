//
//  BookSearchSpotlightView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/21/26.
//

import CoreData
import SwiftUI

/// The ⌘K floating bar for jumping to a book without touching the sidebar filter.
struct BookSearchSpotlightView: View {
  @Environment(BooksViewModel.self) private var viewModel
  @Environment(AnimationSettings.self) private var animationSettings
  @Binding var entry: NavigationEntry?

  var body: some View {
    ZStack {
      if viewModel.isSpotlightPresented {
        SpotlightPanel(search: viewModel.spotlightModel) { bookID in
          withAnimation(animationSettings.selectionSpring) {
            entry = NavigationEntry(selection: .book(bookID))
          }
        }
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.15), value: viewModel.isSpotlightPresented)
  }
}

private struct SpotlightPanel: View {
  private static let width: CGFloat = 520
  private static let cornerRadius: CGFloat = 18
  private static let maxSuggestionRows = 3
  private static let maxBookRows = 6
  private static let coverSize = CGSize(width: 32, height: 48)

  private enum Row: Identifiable {
    case suggestion(BookSearchToken)
    case book(BookSearchResult)

    var id: AnyHashable {
      switch self {
      case .suggestion(let token): AnyHashable(token)
      case .book(let result): AnyHashable(result.book.objectID)
      }
    }
  }

  @Environment(BooksViewModel.self) private var viewModel
  @Bindable var search: SearchViewModel
  let onOpen: (NSManagedObjectID) -> Void

  @FocusState private var isFieldFocused: Bool
  @State private var selectedIndex = 0

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.12)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
      panel
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }
    .defaultFocus($isFieldFocused, true)
    .onAppear {
      search.searchText = ""
      search.tokens = []
      isFieldFocused = true
    }
    .task(id: search.key) {
      viewModel.performSpotlightSearch()
    }
    .onChange(of: search.key) {
      selectedIndex = 0
    }
    #if os(macOS)
      .onExitCommand(perform: dismiss)
    #endif
  }

  private var rows: [Row] {
    let suggestions = search.suggestedTokens.prefix(Self.maxSuggestionRows).map(Row.suggestion)
    guard search.hasActiveSearch else { return suggestions }
    return suggestions + viewModel.spotlightResults.prefix(Self.maxBookRows).map(Row.book)
  }

  // MARK: - Panel

  private var panel: some View {
    VStack(alignment: .leading, spacing: 0) {
      inputRow
      let rows = self.rows
      if !rows.isEmpty {
        Divider()
          .opacity(0.5)
        VStack(spacing: 2) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            rowButton(row, isSelected: index == selectedIndex)
              .onHover { isHovering in
                if isHovering {
                  selectedIndex = index
                }
              }
          }
        }
        .padding(6)
      } else if search.hasActiveSearch {
        Divider()
          .opacity(0.5)
        Text("No results")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 18)
          .padding(.vertical, 14)
      }
    }
    .frame(maxWidth: Self.width)
    .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .glassEffect(
      .regular.tint(Color.botanicalSurfaceTint.opacity(0.35)),
      in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    )
    .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
  }

  private var inputRow: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.title3)
        .foregroundStyle(.secondary)
      ForEach(search.tokens) { token in
        Button {
          search.tokens.removeAll { $0 == token }
        } label: {
          Text(token.label)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.botanicalSage.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .help("Remove \(token.label)")
      }
      TextField("Search books", text: $search.searchText)
        .textFieldStyle(.plain)
        .font(.title3)
        .focused($isFieldFocused)
        .onSubmit(activateSelection)
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.escape) {
          dismiss()
          return .handled
        }
        .onKeyPress(.delete) {
          guard search.searchText.isEmpty, !search.tokens.isEmpty else { return .ignored }
          search.tokens.removeLast()
          return .handled
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  // MARK: - Rows

  private func rowButton(_ row: Row, isSelected: Bool) -> some View {
    Button {
      activate(row)
    } label: {
      rowContent(row)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.sidebarSelectionFill())
      }
    }
  }

  @ViewBuilder
  private func rowContent(_ row: Row) -> some View {
    switch row {
    case .suggestion(let token):
      HStack(spacing: 12) {
        Image(systemName: token.systemImage)
          .foregroundStyle(Color.botanicalSage)
          .frame(width: Self.coverSize.width)
        Text(token.label)
      }
    case .book(let result):
      HStack(spacing: 12) {
        BookCoverImageView(book: result.book, targetSize: Self.coverSize)
          .frame(width: Self.coverSize.width, height: Self.coverSize.height)
        BookSearchResultLabels(book: result.book, match: result.match)
        Spacer(minLength: 8)
        if let rating = result.book.rating?.intValue, rating > 0 {
          StarRatingView(
            rating: rating,
            size: 9,
            fillColor: Color.botanicalGold.opacity(0.7),
            emptyColor: Color.botanicalGold.opacity(0.18)
          )
        }
      }
    }
  }

  // MARK: - Actions

  private func moveSelection(by offset: Int) -> KeyPress.Result {
    let rowCount = rows.count
    guard rowCount > 0 else { return .ignored }
    selectedIndex = min(max(selectedIndex + offset, 0), rowCount - 1)
    return .handled
  }

  private func activateSelection() {
    let rows = self.rows
    guard rows.indices.contains(selectedIndex) else { return }
    activate(rows[selectedIndex])
  }

  private func activate(_ row: Row) {
    switch row {
    case .suggestion(let token):
      search.tokens.append(token)
      isFieldFocused = true
    case .book(let result):
      onOpen(result.book.objectID)
      dismiss()
    }
  }

  private func dismiss() {
    viewModel.isSpotlightPresented = false
  }
}
