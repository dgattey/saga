//
//  SearchableDTO.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//


import Foundation
import Ifrit

/// Every model that needs to be filterable should conform to this
protocol SearchableDTO: AnyObject, Identifiable, Searchable {
    // List the key paths to properties you want to be searchable/sortable
    static var searchableKeyPaths: [PartialKeyPath<Self>] { get }
    
    /// Converts a property at a key path to a string for search/sort
    func stringValue(for keyPath: PartialKeyPath<Self>) -> String
}

extension SearchableDTO {
    // Provide all searchable fields as FuseProp
    var properties: [FuseProp] {
        Self.searchableKeyPaths.map { keyPath in
            FuseProp(self.stringValue(for: keyPath))
        }
    }
    
    /// Returns all strings that should be considered for fuzzy search.
    func searchableStrings() -> [String] {
        Self.searchableKeyPaths.map { stringValue(for: $0) }
    }
}
