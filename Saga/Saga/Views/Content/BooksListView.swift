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
    let onFileDrop: ([URL]) async -> Void

    var body: some View {
        FileDropZoneContainer(onDrop: onFileDrop) {
            List {
                ForEach(books, id: \.id) { book in
                    BookView(book: book)
                }
                .onDelete(perform: onDelete)
            }
        }
        .navigationTitle("All books")
    }
}
