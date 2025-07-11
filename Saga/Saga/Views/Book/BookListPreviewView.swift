//
//  BookListPreviewView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the list preview version of a book
struct BookListPreviewView: View {
    var book: Book
    
    var body: some View {
        HStack(spacing: 8) {
            BookCoverImageView(book: book)
                .frame(height: 64, alignment: .center)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title ?? book.id)
                    .font(.headline)
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                }
                BookStatusView(book: book)
            }
        }
        .padding(.vertical, 4)
    }
}
