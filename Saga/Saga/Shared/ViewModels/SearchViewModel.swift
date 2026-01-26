//
//  SearchViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/7/25.
//

import Ifrit
import SwiftUI

struct SearchHighlightResult<Model: SearchableModel> {
  let model: Model
  private let fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString]

  init(model: Model, fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString] = [:]) {
    self.model = model
    self.fieldHighlights = fieldHighlights
  }

  func highlighted(for field: PartialKeyPath<Model.DTOType>) -> AttributedString? {
    fieldHighlights[field]
  }
}

final class SearchViewModel: ObservableObject {
  @Published var searchText = ""
  private var searchTask: Task<Void, Never>? = nil

  /// TODO: @dgattey this is performant but doesn't allow searching anything but the starts of strings, so the review for example isn't well searchable
  /// The shared fuse configured object for searching for this model
  private let fuse = Fuse(distance: 100, threshold: 0.3, tokenize: true)

  /// Fuzzy searches for a given search term using an array of fetched results, using a Task
  func search<Model: SearchableModel>(
    in allResults: [Model],
    debounce: Duration? = nil,
    completion: @escaping ([SearchHighlightResult<Model>]) -> Void
  ) {
    searchTask?.cancel()
    let query = searchText
    searchTask = Task(priority: .background) {
      if let debounce {
        try? await Task.sleep(for: debounce)
      }
      guard !Task.isCancelled else { return }
      let filteredResults = await runFuzzySearch(in: allResults, query: query)
      guard !Task.isCancelled else { return }
      await MainActor.run { completion(filteredResults) }
    }
  }

  /// Actually runs the results using current text/etc
  private func runFuzzySearch<Model: SearchableModel>(
    in allResults: [Model],
    query: String
  ) async -> [SearchHighlightResult<Model>] {
    guard !query.isEmpty else {
      return allResults.map { SearchHighlightResult(model: $0) }
    }

    let dtos = allResults.map { $0.toDTO() }

    // Run Ifrit search
    let results = await fuse.search(
      query,
      in: dtos,
      by: \.fuzzySearchableProperties
    )

    let keyPaths = Model.DTOType.fuzzySearchKeyPaths

    return results.map { result in
      let dto = dtos[result.index]
      let model = allResults[result.index]
      var fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString] = [:]

      for match in result.results {
        let matchValue = match.value

        // Find the matching key path in fuzzySearchKeyPaths
        if let matchingKeyPath = keyPaths.first(where: { keyPath in
          guard let fieldValue = dto[keyPath: keyPath] as? String else { return false }
          return fieldValue.contains(match.value)
        }) {
          let highlighted = makeHighlightedAttributedString(
            from: matchValue,
            ranges: match.ranges
          )

          fieldHighlights[matchingKeyPath] = highlighted
        }
      }

      return SearchHighlightResult(
        model: model,
        fieldHighlights: fieldHighlights
      )
    }
  }

  /// Creates attributed string for the search results from a range
  func makeHighlightedAttributedString(
    from value: String,
    ranges: [ClosedRange<Int>],
    highlightColor: Color = .accent.opacity(0.5)
  ) -> AttributedString {
    // Start with a styled, mutable AttributedString
    var attributed = AttributedString(value)

    // Loop over the character index ranges (ClosedRange<Int>)
    for characterRange in ranges {
      // Safely ensure range is within string bounds
      guard characterRange.lowerBound >= 0,
        characterRange.upperBound < value.count
      else {
        continue
      }

      // Get String.Index equivalents of Int character positions
      let startIndex = value.index(value.startIndex, offsetBy: characterRange.lowerBound)
      let endIndex = value.index(value.startIndex, offsetBy: characterRange.upperBound + 1)

      // Use text between start and end to find range in the attributed string
      let substring = value[startIndex..<endIndex]
      let rangeLength = substring.count

      // Calculate AttributedString indices
      let attrStart = attributed.index(
        attributed.startIndex, offsetByCharacters: characterRange.lowerBound)
      let attrEnd = attributed.index(attrStart, offsetByCharacters: rangeLength)

      let attributedRange = attrStart..<attrEnd

      // Apply styling
      attributed[attributedRange].backgroundColor = highlightColor
    }

    return attributed
  }
}
