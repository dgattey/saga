//
//  BooksListView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct BooksListView: View {
    @Binding var books: [Book]
    let onDelete: (IndexSet) -> Void

    var body: some View {
        List {
            ForEach(books, id: \.id) { book in
                BookView(book: book)
            }
            .onDelete(perform: onDelete)
        }
        .navigationTitle("All books")
    }
}
