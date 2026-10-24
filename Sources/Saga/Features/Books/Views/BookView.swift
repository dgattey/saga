//
//  BookView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the navigation link item of a book for use in a list
struct BookView: View {
  var result: BookSearchResult

  var body: some View {
    NavigationLink {
      BookContentView(book: result.book)
    } label: {
      BookListPreviewView(result: result)
        .padding(.vertical, 4)
    }
  }
}
