//
//  BooksViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// Contains all our books and allows for filtering
class BooksViewModel: ObservableObject {
    @Published var filteredBooks: [SearchHighlightResult<Book>] = []
    @Published var searchModel = SearchViewModel()

    func performSearch(with books: FetchedResults<Book>) {
        searchModel.search(in: sorted(from: books)) { self.filteredBooks = $0 }
    }
    
    /// Unfinished books at the top, then date descending with either finished or start, then title comparison. Most recent first.
    func sorted(from books: FetchedResults<Book>) -> [Book] {
        return books.sorted { a, b in
            // 1. Unfinished books come first
            let aUnfinished = a.readDateFinished == nil
            let bUnfinished = b.readDateFinished == nil
            if aUnfinished != bUnfinished {
                return aUnfinished && !bUnfinished
            }
            
            // 2. Use the most recent of `readDateFinished` or `readDateStarted`
            let aDate = a.readDateFinished ?? a.readDateStarted ?? .distantPast
            let bDate = b.readDateFinished ?? b.readDateStarted ?? .distantPast
            if aDate != bDate {
                return aDate > bDate // More recent first
            }
            
            // 3. Tie-breaker: localized title comparison
            return (a.title ?? "").localizedCompare(b.title ?? "") == .orderedAscending
        }
    }

}
