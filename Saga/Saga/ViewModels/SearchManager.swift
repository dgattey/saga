//
//  SearchManager.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import Ifrit
import SwiftUI

struct SearchManager {
    
    static let shared = SearchManager()
    
    private let fuse = Fuse(threshold: 0.4, tokenize: true)
    
    private init() {}
    
    /// Fuzzy searches for a given search term using an array of fetched results
    func search<Model: SearchableModel>(for searchText: String,
                                        in fetchedResults: FetchedResults<Model>) async -> Array<Model> {
        let array = Array(fetchedResults)
        guard !searchText.isEmpty else {
            return array
        }
        let results = await fuse.search(searchText, in: array.map{ $0.toDTO() }, by: \.properties)
        return results.map { array[$0.index] }
    }
}
