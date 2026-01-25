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
  /// List the key paths for properties that are themselves searchable
  static var nestedSearchableDTOKeyPaths: [PartialKeyPath<Self>] { get }

  /// List the key paths to properties you want to be fuzzy searchable
  static var fuzzySearchKeyPaths: [PartialKeyPath<Self>] { get }
}

extension SearchableDTO {
  // By default, no nested models
  static var nestedSearchableDTOKeyPaths: [PartialKeyPath<Self>] { [] }

  // Converts all nested searchable DTO paths to objects
  private var nestedSearchableDTOs: [any SearchableDTO] {
    return Self.nestedSearchableDTOKeyPaths.compactMap { keyPath in
      return self[keyPath: keyPath] as? any SearchableDTO
    }
  }

  // Converts all searchable field values to `FuseProp`s for fuzzy searching
  var fuzzySearchableProperties: [FuseProp] {
    let fuzzySearchProps = Self.fuzzySearchKeyPaths.map { keyPath in
      FuseProp(self.stringValue(for: keyPath))
    }
    let nestedFuzzyProps = nestedSearchableDTOs.flatMap { dto in dto.fuzzySearchableProperties
    }
    return fuzzySearchProps + nestedFuzzyProps
  }

  /// Converts a property at a key path to a string for search/sort
  private func stringValue(for keyPath: PartialKeyPath<Self>) -> String {
    return self[keyPath: keyPath] as? String ?? ""
  }
}
