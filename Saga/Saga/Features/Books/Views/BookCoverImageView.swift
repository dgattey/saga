//
//  BookCoverImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import SwiftUI

/// Creates a stylized version of the cover image, async loaded
struct BookCoverImageView: View {
    static let coverAspectRatio: CGFloat = 1 / 1.5

    let book: Book
    
    var body: some View {
        AssetImageView(asset: book.coverImage)
            .aspectRatio(Self.coverAspectRatio, contentMode: .fit)
            .cornerRadius(6)
    }
}
