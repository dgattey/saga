//
//  BooksListView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct BooksListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var books: [Book]
    let onDelete: (IndexSet) -> Void

    var body: some View {
        FileDropZoneContainer(onDrop: handleCsvFileDrop) {
            List {
                ForEach(books, id: \.id) { book in
                    BookView(book: book)
                }
                .onDelete(perform: onDelete)
            }
        }
        .navigationTitle("All books")
    }
    
    /// Discard all but the csv files, and parse them
    private func handleCsvFileDrop(_ fileUrls: [URL]) async {
        do {
            for fileUrl in fileUrls {
                if !fileUrl.pathExtension.lowercased().contains("csv") {
                    continue
                }
                try await GoodreadsCSVParser.parse(into: viewContext, from: fileUrl)
            }
        } catch {
            print("CSV file parse failed with error: \(error)")
        }
    }
}
