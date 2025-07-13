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
        book.author ?? "Unknown author"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            BookCoverImageView(book: book)
                .frame(height: 256, alignment: .center)
            titleView
            authorView
            Text(book.isbn?.stringValue ?? "No ISBN")
            Text(book.coverImage?.assetURL?.absoluteString ?? "No image URL")
            Text(book.readDateStarted?.formatted(date: .complete, time: .omitted) ?? "Not started")
            Text(book.readDateFinished?.formatted(date: .complete, time: .omitted) ?? "Not finished")
            Text(book.rating?.stringValue ?? "No rating")
            Text(book.reviewDescription?.description ?? "No review")
        }
        .textSelection(.enabled)
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
