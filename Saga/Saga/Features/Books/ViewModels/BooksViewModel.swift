//
//  BooksViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// Contains all our books and allows for filtering
class BooksViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredBooks: [Book] = []
    private var searchTask: Task<Void, Never>? = nil

    func performSearch(with books: FetchedResults<Book>) {
        searchTask?.cancel()
        searchTask = Task(priority: .background) {
            let results = await SearchManager.shared.search(for: searchText, in: books)
            if !Task.isCancelled {
                await MainActor.run { self.filteredBooks = results }
            }
        }
    }
}
