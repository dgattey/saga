//
//  OpenLibraryAPIService.swift
//  Saga
//
//  Created by Dylan Gattey on 7/12/25.
//

import Foundation

private struct Constants {
  static let apiBaseURL = "https://openlibrary.org"
  static let coverImagesBaseURL = "https://covers.openlibrary.org"
  static let maxSearchCoverCandidates = 4
  static let preferredCoverBytes = 40_000
}

private struct SearchResponse: Decodable {
  let docs: [Doc]?
}

private struct Doc: Decodable {
  let title: String?
  let authorName: [String]?
  let language: [String]?
  let coverI: Int?
  let coverEditionKey: String?

  enum CodingKeys: String, CodingKey {
    case title
    case authorName = "author_name"
    case language
    case coverI = "cover_i"
    case coverEditionKey = "cover_edition_key"
  }
}

/// Contains functions to work with the OpenLibrary APIs for cover image lookup
struct OpenLibraryAPIService {

  private init() {}

  /// Fetches a cover image URL for a title/author by using OpenLibrary search cover IDs
  static func coverImageURL(forTitle title: String, author: String) async throws -> String? {
    try await bestCoverCandidate(forTitle: title, author: author)?.url
  }

  /// Picks the best OpenLibrary cover candidate for an ISBN + title/author
  static func bestCoverCandidate(forISBN isbn: String, title: String, author: String) async throws
    -> CoverImageCandidate?
  {
    let isbnCandidate = try await coverCandidate(forISBN: isbn)
    if let isbnCandidate,
      isbnCandidate.bytes >= Constants.preferredCoverBytes
    {
      return isbnCandidate
    }
    let searchCandidate = try await bestCoverCandidate(forTitle: title, author: author)
    return [isbnCandidate, searchCandidate].compactMap { $0 }.max(by: { $0.bytes < $1.bytes })
  }

  /// Fetches the search response for a title/author combo
  private static func searchResponse(forTitle title: String, author: String) async throws
    -> SearchResponse?
  {
    guard var components = URLComponents(string: "\(Constants.apiBaseURL)/search.json") else {
      return nil
    }
    let query = "\(cleanedTitle(title)) \(author)"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(
        name: "fields",
        value: "title,author_name,language,cover_i,cover_edition_key"
      ),
      URLQueryItem(name: "lang", value: "en"),
    ]
    guard let url = components.url else { return nil }
    let (data, response) = try await NetworkCache.urlSession.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      LoggerService.log(
        "Search response failed for \"\(title)\": \(response)",
        level: .error,
        surface: .network
      )
      return nil
    }
    return try? JSONDecoder().decode(SearchResponse.self, from: data)
  }

  private static func coverCandidate(forISBN isbn: String) async throws -> CoverImageCandidate? {
    guard
      let url = URL(string: "\(Constants.coverImagesBaseURL)/b/isbn/\(isbn)-L.jpg?default=false")
    else {
      return nil
    }
    return try await CoverImageCandidate.from(url: url)
  }

  private static func bestCoverCandidate(forTitle title: String, author: String) async throws
    -> CoverImageCandidate?
  {
    let searchResponse = try await searchResponse(forTitle: title, author: author)
    guard let response = searchResponse,
      let docs = response.docs, !docs.isEmpty
    else {
      return nil
    }
    let normalizedTitle = normalized(cleanedTitle(title))
    let normalizedAuthor = normalized(author)
    let englishDocs = docs.filter { $0.language?.contains("eng") == true }
    let prioritizedDocs = prioritizedDocGroups(
      from: englishDocs.isEmpty ? docs : englishDocs,
      normalizedTitle: normalizedTitle,
      normalizedAuthor: normalizedAuthor
    )
    var checked = 0
    var best: CoverImageCandidate?
    for docGroup in prioritizedDocs {
      for doc in docGroup {
        for candidate in coverURLCandidates(from: doc) {
          guard checked < Constants.maxSearchCoverCandidates else {
            return best
          }
          checked += 1
          if let coverCandidate = try await CoverImageCandidate.from(url: candidate) {
            if best == nil || coverCandidate.bytes > best?.bytes ?? 0 {
              best = coverCandidate
            }
          }
        }
      }
    }
    return best
  }

  private static func coverURLCandidates(from doc: Doc) -> [URL] {
    var urls: [URL] = []
    if let coverEditionKey = doc.coverEditionKey,
      let url = URL(
        string: "\(Constants.coverImagesBaseURL)/b/olid/\(coverEditionKey)-L.jpg?default=false")
    {
      urls.append(url)
    }
    if let coverI = doc.coverI,
      let url = URL(string: "\(Constants.coverImagesBaseURL)/b/id/\(coverI)-L.jpg?default=false")
    {
      urls.append(url)
    }
    return urls
  }

  private static func prioritizedDocGroups(
    from docs: [Doc],
    normalizedTitle: String,
    normalizedAuthor: String
  ) -> [[Doc]] {
    let authorMatchesDocs = docs.filter {
      authorMatches($0.authorName, normalizedAuthor: normalizedAuthor)
    }
    let titleMatchesDocs = docs.filter { titleMatches($0.title, normalizedTitle: normalizedTitle) }
    let authorTitleMatchesDocs = authorMatchesDocs.filter {
      titleMatches($0.title, normalizedTitle: normalizedTitle)
    }
    return [authorTitleMatchesDocs, authorMatchesDocs, titleMatchesDocs, docs].filter {
      !$0.isEmpty
    }
  }

  private static func cleanedTitle(_ title: String) -> String {
    title.replacingOccurrences(
      of: #" \([^(#)]*#\d+\)$"#,
      with: "",
      options: .regularExpression
    )
  }

  private static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .components(separatedBy: .alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined()
  }

  private static func titleMatches(_ candidate: String?, normalizedTitle: String) -> Bool {
    guard let candidate else { return false }
    let normalizedCandidate = normalized(candidate)
    guard !normalizedCandidate.isEmpty, !normalizedTitle.isEmpty else { return false }
    return normalizedCandidate == normalizedTitle
      || normalizedCandidate.contains(normalizedTitle)
      || normalizedTitle.contains(normalizedCandidate)
  }

  private static func authorMatches(_ candidates: [String]?, normalizedAuthor: String) -> Bool {
    guard let candidates, !normalizedAuthor.isEmpty else { return false }
    return candidates.contains { candidate in
      let normalizedCandidate = normalized(candidate)
      guard !normalizedCandidate.isEmpty else { return false }
      return normalizedCandidate == normalizedAuthor
        || normalizedCandidate.contains(normalizedAuthor)
        || normalizedAuthor.contains(normalizedCandidate)
    }
  }
}
