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
                BooksListView(books: $viewModel.filteredBooks, onDelete: deleteBooks)
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
                    ContentViewToolbar(add: addBook)
                }
                EmptyContentView()
            }
        }
    }

    private func addBook() {
        withAnimation {
            _ = Book(context: viewContext, title: "Book \(UUID().uuidString)")
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
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
