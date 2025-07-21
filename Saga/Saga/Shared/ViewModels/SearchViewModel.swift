//
//  SearchViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import Ifrit
import SwiftUI

class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @State private var searchTask: Task<Void, Never>? = nil
    
    /// The shared fuse configured object for searching for this model
    private let fuse = Fuse(distance: 5000, threshold: 0.3, tokenize: true)
    
    /// Fuzzy searches for a given search term using an array of fetched results, using a Task
    func search<Model: SearchableModel>(in allResults: FetchedResults<Model>, completion: @escaping ([Model]) -> Void) {
        searchTask?.cancel()
        searchTask = Task(priority: .background) {
            let filteredResults = await runFuzzySearch(in: allResults)
            if !Task.isCancelled {
                await MainActor.run { completion(filteredResults) }
            }
        }
    }
    
    /// Actually runs the results using current text/etc
    private func runFuzzySearch<Model: SearchableModel>(in allResults: FetchedResults<Model>) async -> [Model] {
        let array = Array(allResults)
        guard !searchText.isEmpty else {
            return array
        }
        let results = await fuse.search(
            searchText,
            in: array.map{ $0.toDTO() },
            by: \.fuzzySearchableProperties)
        return results.map { array[$0.index] }
    }
}
