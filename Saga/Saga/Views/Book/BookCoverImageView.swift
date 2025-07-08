//
//  BookCoverImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import SwiftUI

private let coverAspectRatio: CGFloat = 1/1.5

/// Creates a stylized version of the cover image, async loaded
struct BookCoverImageView: View {
    var book: Book
    
    var body: some View {
        AssetImageView(asset: book.coverImage)
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .cornerRadius(6)
    }
}
