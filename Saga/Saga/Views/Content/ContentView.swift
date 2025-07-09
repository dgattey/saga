//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var viewModel = BooksViewModel()
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.readDateStarted, ascending: false)],
        animation: .default) private var books: FetchedResults<Book>

    var body: some View {
        ScrollViewReader { proxy in
            NavigationView {
                BooksListView(books: $viewModel.filteredBooks,
                              onDelete: deleteBooks,
                              onFileDrop: handleCsvFileDrop)
                .searchable(text: $viewModel.searchText)
                .onAppear { viewModel.performSearch(with: books) }
                .onChange(of: Array(books)) {
                    viewModel.performSearch(with: books)
                }
                .onChange(of: viewModel.searchText) {
                    viewModel.performSearch(with: books)
                }
                .onChange(of: viewModel.filteredBooks) {
                    if let firstBook = viewModel.filteredBooks.first {
                        proxy.scrollTo(firstBook.id, anchor: .top)
                    }
                }
                .toolbar {
                    ContentViewToolbar()
                }
                EmptyContentView()
            }
        }
    }
    
    /// Discard all but the csv files, and parse them
    private func handleCsvFileDrop(_ fileUrls: [URL]) async {
        do {
            for fileUrl in fileUrls {
                if !fileUrl.pathExtension.lowercased().contains("csv") {
                    continue
                }
                try await BookCSVParser.parseCSV(into: viewContext, from: fileUrl)
            }
        } catch {
            print("CSV file parse failed with error: \(error)")
        }
    }

    private func deleteBooks(offsets: IndexSet) {
        withAnimation {
            offsets.map { books[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
