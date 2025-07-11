//
//  BookView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the navigation link item of a book for use in a list
struct BookView: View {
    var book: Book
    
    var body: some View {
        NavigationLink {
            BookContentView(book: book)
        } label: {
            BookListPreviewView(book: book)
        }
    }
}
