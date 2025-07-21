//
//  SearchViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import Ifrit
import SwiftUI

struct SearchViewModel {
    /// The shared fuse configured object for searching for this model
    private let fuse = Fuse(distance: 5000, threshold: 0.3, tokenize: true)
    
    /// Fuzzy searches for a given search term using an array of fetched results
    func search<Model: SearchableModel>(for searchText: String,
                                        in fetchedResults: FetchedResults<Model>) async -> Array<Model> {
        let array = Array(fetchedResults)
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
