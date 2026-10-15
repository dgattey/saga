//
//  BookListPreviewView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the list preview version of a book
struct BookListPreviewView: View {
  var result: SearchHighlightResult<Book>
  @ObservedObject private var book: Book

  init(result: SearchHighlightResult<Book>) {
    self.result = result
    self._book = ObservedObject(wrappedValue: result.model)
  }

  var body: some View {
    HStack(spacing: 8) {
      BookCoverImageView(book: book)
        .frame(height: 64, alignment: .center)
        .controlSize(.small)
      VStack(alignment: .leading, spacing: 4) {
        if let highlightedTitle = result.highlighted(for: \.title) {
          Text(highlightedTitle)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
        } else {
          Text(book.title ?? book.id)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        if let author = book.author {
          if let highlightedAuthor = result.highlighted(for: \.author) {
            Text(highlightedAuthor)
              .font(.subheadline)
              .lineLimit(1)
              .truncationMode(.tail)
          } else {
            Text(author)
              .font(.subheadline)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
      }
      Spacer()
      BookStatusView(book: book)
    }
  }
}
