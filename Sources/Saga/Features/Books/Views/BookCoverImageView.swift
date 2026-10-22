//
//  BookCoverImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import SwiftUI

/// Creates a stylized version of the cover image, async loaded
struct BookCoverImageView: View {
  nonisolated static let coverAspectRatio: CGFloat = 1 / 1.5

  let book: Book
  let targetSize: CGSize?

  init(book: Book, targetSize: CGSize? = nil) {
    self.book = book
    self.targetSize = targetSize
  }

  var body: some View {
    AssetImageView(url: book.displayCoverURL, targetSize: targetSize)
      .aspectRatio(Self.coverAspectRatio, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}
