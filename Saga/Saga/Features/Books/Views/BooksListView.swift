//
//  BooksListView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct BooksListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var viewModel: BooksViewModel
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.readDateStarted, ascending: false)],
        animation: .default) private var books: FetchedResults<Book>

    var body: some View {
        List {
            Section {
                ForEach(viewModel.filteredBooks, id: \.model.id) { result in
                    BookView(result: result)
                }
                .onDelete(perform: deleteBooks)
            }
        }
#if os(macOS)
        .frame(minWidth: 200, idealWidth: 300)
#endif
        .onAppear { viewModel.performSearch(with: books) }
        .onChange(of: Array(books)) {
            viewModel.performSearch(with: books)
        }
        .onChange(of: viewModel.searchModel.searchText) {
            viewModel.performSearch(with: books)
        }
        .searchable(text: $viewModel.searchModel.searchText,
                    placement: .sidebar)
        .navigationTitle("All books")
    }
    
    /// Deletes books from our view context
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
