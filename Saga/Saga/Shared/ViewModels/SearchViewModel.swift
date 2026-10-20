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
  let index: Int
  private let fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString]

  init(
    model: Model,
    index: Int = 0,
    fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString] = [:]
  ) {
    self.model = model
    self.index = index
    self.fieldHighlights = fieldHighlights
  }

  func highlighted(for field: PartialKeyPath<Model.DTOType>) -> AttributedString? {
    fieldHighlights[field]
  }
}

@Observable
final class SearchViewModel {
  var searchText = ""
  @ObservationIgnored private var searchTask: Task<Void, Never>? = nil

  var hasActiveSearch: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// TODO: @dgattey this is performant but doesn't allow searching anything but the starts of strings, so the review for example isn't well searchable
  /// The shared fuse configured object for searching for this model
  @ObservationIgnored private let fuse = Fuse(distance: 100, threshold: 0.3, tokenize: true)

  /// Fuzzy searches for a given search term using an array of fetched results, using a Task
  func search<Model: SearchableModel>(
    in allResults: [Model],
    debounce: Duration? = nil,
    makeDTOs: (() -> [Model.DTOType])? = nil,
    completion: @escaping ([SearchHighlightResult<Model>]) -> Void
  ) {
    searchTask?.cancel()
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      if let debounce {
        searchTask = Task { @MainActor in
          try? await Task.sleep(for: debounce)
          guard !Task.isCancelled else { return }
          completion(
            allResults.enumerated().map { index, model in
              SearchHighlightResult(model: model, index: index)
            }
          )
        }
      } else {
        searchTask = nil
        completion(
          allResults.enumerated().map { index, model in
            SearchHighlightResult(model: model, index: index)
          }
        )
      }
      return
    }

    searchTask = Task(priority: .userInitiated) {
      if let debounce {
        try? await Task.sleep(for: debounce)
      }
      guard !Task.isCancelled else { return }
      let dtos = await MainActor.run {
        makeDTOs?() ?? allResults.map { $0.toDTO() }
      }
      guard !Task.isCancelled else { return }
      let filteredResults = await runFuzzySearch(
        in: allResults,
        dtos: dtos,
        query: query
      )
      guard !Task.isCancelled else { return }
      await MainActor.run { completion(filteredResults) }
    }
  }

  /// Actually runs the results using current text/etc
  private func runFuzzySearch<Model: SearchableModel>(
    in allResults: [Model],
    dtos: [Model.DTOType],
    query: String
  ) async -> [SearchHighlightResult<Model>] {
    guard !query.isEmpty else {
      return allResults.enumerated().map { index, model in
        SearchHighlightResult(model: model, index: index)
      }
    }

    // Run Ifrit search
    let results = await fuse.search(
      query,
      in: dtos,
      by: \.fuzzySearchableProperties
    )

    let orderedResults = results.sorted { $0.index < $1.index }
    let keyPaths = Model.DTOType.fuzzySearchKeyPaths

    return orderedResults.enumerated().map { outputIndex, result in
      let dto = dtos[result.index]
      let model = allResults[result.index]
      var fieldHighlights: [PartialKeyPath<Model.DTOType>: AttributedString] = [:]

      for match in result.results {
        let matchValue = match.value

        // Find the matching key path in fuzzySearchKeyPaths
        if let matchingKeyPath = keyPaths.first(where: { keyPath in
          guard let fieldValue = dto[keyPath: keyPath] as? String else { return false }
          return fieldValue == matchValue || fieldValue.contains(matchValue)
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
        index: outputIndex,
        fieldHighlights: fieldHighlights
      )
    }
  }

  /// Creates attributed string for the search results from a range
  func makeHighlightedAttributedString(
    from value: String,
    ranges: [ClosedRange<Int>],
    highlightColor: Color = Color("AccentColor").opacity(0.5)
  ) -> AttributedString {
    // Start with a styled, mutable AttributedString
    var attributed = AttributedString(value)
    let valueCount = value.count

    // Loop over the character index ranges (ClosedRange<Int>)
    for characterRange in ranges {
      // Safely ensure range is within string bounds
      guard characterRange.lowerBound >= 0,
        characterRange.upperBound < valueCount
      else {
        continue
      }

      let rangeLength = characterRange.count

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
