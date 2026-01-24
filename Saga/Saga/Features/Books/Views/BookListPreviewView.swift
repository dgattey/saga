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
    
    private var book: Book {
        result.model
    }
    
    var body: some View {
        HStack(spacing: 8) {
            BookCoverImageView(book: book)
                .frame(height: 64, alignment: .center)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.highlighted(for: \.title) ?? AttributedString(book.title ?? book.id))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let author = book.author {
                    Text(result.highlighted(for: \.author) ?? AttributedString(author))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            BookStatusView(book: book)
        }
    }
}
