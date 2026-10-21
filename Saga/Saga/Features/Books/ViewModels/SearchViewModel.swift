//
//  SearchViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import SwiftUI

struct BookSearchResult {
  let book: Book
  let index: Int
  var match = BookSearchMatch()
}

/// Query text, applied tokens, and debounced background search for one search surface.
@Observable
final class SearchViewModel {
  struct Key: Equatable {
    let text: String
    let tokens: [BookSearchToken]
  }

  var searchText = ""
  var tokens: [BookSearchToken] = [] {
    didSet {
      guard tokens.count > oldValue.count else { return }
      dropLastWord()
    }
  }
  private(set) var suggestedTokens: [BookSearchToken] = []
  @ObservationIgnored private var searchTask: Task<Void, Never>? = nil

  var key: Key { Key(text: searchText, tokens: tokens) }

  var query: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var hasActiveSearch: Bool {
    !query.isEmpty || !tokens.isEmpty
  }

  /// Searches `books` (already in display order) off the main thread. `makeDocuments` runs on the
  /// main actor after the debounce and must return one document per book.
  func search(
    in books: [Book],
    debounce: Duration? = nil,
    makeDocuments: @escaping () -> [BookSearchDocument],
    completion: @escaping ([BookSearchResult]) -> Void
  ) {
    searchTask?.cancel()
    suggestedTokens = BookSearchToken.suggestions(
      for: searchText,
      years: Array(Set(books.compactMap(\.readYear))).sorted(by: >),
      excluding: tokens
    )
    guard hasActiveSearch else {
      let results = books.enumerated().map { BookSearchResult(book: $1, index: $0) }
      guard let debounce else {
        searchTask = nil
        completion(results)
        return
      }
      searchTask = Task { @MainActor in
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return }
        completion(results)
      }
      return
    }

    let query = query
    let tokens = tokens
    searchTask = Task(priority: .userInitiated) {
      if let debounce {
        try? await Task.sleep(for: debounce)
      }
      guard !Task.isCancelled else { return }
      let documents = await MainActor.run { makeDocuments() }
      let hits = BookSearchEngine.search(query, tokens: tokens, in: documents)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        completion(
          hits.enumerated().map { outputIndex, hit in
            BookSearchResult(book: books[hit.index], index: outputIndex, match: hit.match)
          }
        )
      }
    }
  }

  /// Removes the partially typed word a suggested token just replaced.
  private func dropLastWord() {
    let trimmed = searchText.trimmingCharacters(in: .whitespaces)
    guard let lastSpace = trimmed.lastIndex(where: \.isWhitespace) else {
      searchText = ""
      return
    }
    searchText = String(trimmed[...lastSpace])
  }
}
