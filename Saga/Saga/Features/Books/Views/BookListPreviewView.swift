//
//  BookListPreviewView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the list preview version of a book
struct BookListPreviewView: View {
  private static let coverHeight: CGFloat = 64
  private static let coverSize = CGSize(
    width: coverHeight * BookCoverImageView.coverAspectRatio,
    height: coverHeight
  )

  var result: BookSearchResult
  @ObservedObject private var book: Book

  init(result: BookSearchResult) {
    self.result = result
    self._book = ObservedObject(wrappedValue: result.book)
  }

  var body: some View {
    HStack(spacing: 8) {
      BookCoverImageView(book: book, targetSize: Self.coverSize)
        .frame(width: Self.coverSize.width, height: Self.coverSize.height, alignment: .center)
        .controlSize(.small)
      BookSearchResultLabels(book: book, match: result.match)
      Spacer()
      BookStatusView(book: book)
    }
  }
}

/// Title, author, and (for review matches) one muted excerpt line, with matches in warm gold.
struct BookSearchResultLabels: View {
  @ObservedObject var book: Book
  let match: BookSearchMatch

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(highlighted(book.title ?? book.id, ranges: match.titleRanges))
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
      if let author = book.author {
        Text(highlighted(author, ranges: match.authorRanges))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      if let excerpt = match.excerpt {
        Text(highlighted(excerpt.text, ranges: [excerpt.highlight]))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  private func highlighted(_ text: String, ranges: [Range<Int>]) -> AttributedString {
    var attributed = AttributedString(text)
    let characterCount = attributed.characters.count
    for range in ranges where range.lowerBound >= 0 && range.upperBound <= characterCount {
      let start = attributed.index(attributed.startIndex, offsetByCharacters: range.lowerBound)
      let end = attributed.index(start, offsetByCharacters: range.count)
      attributed[start..<end].foregroundColor = .botanicalGold
      attributed[start..<end].backgroundColor = Color.botanicalGold.opacity(0.16)
    }
    return attributed
  }
}
