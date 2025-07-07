//
//  BookContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the full version of a book
struct BookContentView: View {
    var book: Book
    var title: String {
        book.title ?? "Untitled book"
    }
    var author: String {
        book.author ?? "Unknown Author"
    }
    
    var body: some View {
        VStack {
            AssetImageView(asset: book.coverImage)
                .frame(width: 256, height: 256, alignment: .center)
            titleView
            authorView
        }
        .navigationTitle(title)
#if os(macOS)
        .navigationSubtitle(author)
#endif
    }
    
    var titleView: some View {
        Text(title).font(.title)
    }
    
    var authorView: some View {
        Text(author).font(.subheadline)
    }
}
