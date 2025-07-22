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
    @State private var completedCSVImportSteps = 0
    @State private var totalCSVImportSteps = 0

    var body: some View {
        FileDropZoneContainer(
            onDrop: handleCsvFileDrop,
            completedSteps: $completedCSVImportSteps,
            totalSteps: $totalCSVImportSteps
        ) {
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
                try await GoodreadsCSVParser
                    .parse(
                        into: viewContext,
                        from: fileUrl,
                        completedSteps: $completedCSVImportSteps,
                        totalSteps: $totalCSVImportSteps
                    )
            }
        } catch {
            print("CSV file parse failed with error: \(error)")
        }
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
