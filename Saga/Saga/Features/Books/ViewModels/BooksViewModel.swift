//
//  BooksViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// Contains all our books and allows for filtering
class BooksViewModel: ObservableObject {
    @Published var filteredBooks: [Book] = []
    @Published var searchModel = SearchViewModel()

    func performSearch(with books: FetchedResults<Book>) {
        searchModel.search(in: books) { self.filteredBooks = $0 }
    }
}
