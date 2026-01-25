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
  let key: String?
  let title: String?
  let authorName: [String]?
  let language: [String]?
  let coverI: Int?
  let coverEditionKey: String?
  let editions: Editions?

  enum CodingKeys: String, CodingKey {
    case key
    case title
    case authorName = "author_name"
    case language
    case coverI = "cover_i"
    case coverEditionKey = "cover_edition_key"
    case editions
  }
}

private struct Editions: Decodable {
  let docs: [EditionDoc]?
}

private struct EditionDoc: Decodable {
  let title: String?
  let isbn: [String]?
}

private struct EditionsResponse: Decodable {
  let entries: [EditionEntry]?
}

private struct EditionEntry: Decodable {
  let isbn: [String]?
  let languages: [Language]?

  enum CodingKeys: String, CodingKey {
    case isbn = "isbn_13"
    case languages = "languages"
  }
}

private struct Language: Decodable {
  let key: String
}

/// Contains functions to work with the OpenLibrary APIs
struct OpenLibraryAPIService: CoverImageURLProvider {

  private init() {}

  /// Generates a URL for the large cover image, validating size and 404
  static func coverImageURL(forISBN isbn: String) async throws -> String? {
    return try await coverCandidate(forISBN: isbn)?.url
  }

  /// Fetches a cover image URL for a title/author by using OpenLibrary search cover IDs
  static func coverImageURL(forTitle title: String, author: String) async throws -> String? {
    return try await bestCoverCandidate(forTitle: title, author: author)?.url
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
    return bestCandidate(from: [isbnCandidate, searchCandidate].compactMap { $0 })
  }

  /// Fetches an ISBN for a given title/author combo, using the search and editions APIs
  static func isbnFor(title: String, author: String) async throws -> String? {
    let searchResponse = try await searchResponse(forTitle: title, author: author)
    guard let response = searchResponse,
      let docs = response.docs, !docs.isEmpty
    else {
      print("Error: failed to fetch search: \(searchResponse.debugDescription)")
      return nil
    }

    let normalizedTitle = normalized(cleanedTitle(title))
    let normalizedAuthor = normalized(author)
    let englishDocs = docs.filter { $0.language?.contains("eng") == true }
    let docGroups = prioritizedDocGroups(
      from: englishDocs.isEmpty ? docs : englishDocs,
      normalizedTitle: normalizedTitle,
      normalizedAuthor: normalizedAuthor
    )

    for docs in docGroups {
      let exactTitleISBNs = isbnCandidates(
        from: docs, normalizedTitle: normalizedTitle, requireTitleMatch: true)
      if let isbn = preferredISBN(from: exactTitleISBNs) {
        return isbn
      }
      let fallbackISBNs = isbnCandidates(
        from: docs, normalizedTitle: normalizedTitle, requireTitleMatch: false)
      if let isbn = preferredISBN(from: fallbackISBNs) {
        return isbn
      }
    }

    if let workKey = docGroups.compactMap({ $0.first?.key }).first,
      let isbnsFromEditions = try await fetchISBNsFromEditions(forWorkKey: workKey, title: title),
      let isbn = preferredISBN(from: isbnsFromEditions)
    {
      return isbn
    }

    print("Warning: missing ISBNs for \"\(title)\"")
    return nil
  }

  /// Sometimes the search endpoint doesn't return an edition with an ISBN, for whatever reason. This fetches a work specifically to find its ISBN
  /// to fix that problem in limited cases with an extra fetch.
  private static func fetchISBNsFromEditions(forWorkKey workKey: String, title: String) async throws
    -> [String]?
  {
    let editionsResponse = try await editionsResponse(forWorkKey: workKey, title: title)
    guard let response = editionsResponse,
      let editions = response.entries,
      !editions.isEmpty
    else {
      print("Error: empty editions response")
      return nil
    }
    for edition in editions {
      if let langs = edition.languages,
        langs.contains(where: { $0.key == "/languages/eng" })
      {
        return edition.isbn
      }
    }
    print("Error: editions didn't include an isbn for \(title): \(editions)\n")
    return nil
  }

  /// Fetches the search response for a title/author combo, pulling in the title/isbn from the attached editions.
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
        value:
          "key,title,author_name,language,cover_i,cover_edition_key,editions,editions.title,editions.isbn"
      ),
      URLQueryItem(name: "lang", value: "en"),
    ]
    guard let url = components.url else { return nil }
    let (data, response) = try await NetworkCache.urlSession.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      print("Couldn't fetch search response for \"\(title)\": \(response)")
      return nil
    }
    return try? JSONDecoder().decode(SearchResponse.self, from: data)
  }

  /// Fetches the editions response for a given work key
  private static func editionsResponse(forWorkKey workKey: String, title: String) async throws
    -> EditionsResponse?
  {
    let editionsURLString = "\(Constants.apiBaseURL)\(workKey)/editions.json"
    guard let editionsURL = URL(string: editionsURLString) else { return nil }

    let (data, response) = try await NetworkCache.urlSession.data(from: editionsURL)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      print("Couldn't fetch editions response for \"\(title)\": \(response)")
      return nil
    }
    return try? JSONDecoder().decode(EditionsResponse.self, from: data)
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

  private static func bestCandidate(from candidates: [CoverImageCandidate]) -> CoverImageCandidate?
  {
    candidates.max(by: { $0.bytes < $1.bytes })
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

  private static func isbnCandidates(
    from docs: [Doc],
    normalizedTitle: String,
    requireTitleMatch: Bool
  ) -> [String] {
    let editionDocs = docs.compactMap { $0.editions?.docs }.flatMap { $0 }
    let filteredEditions =
      requireTitleMatch
      ? editionDocs.filter { titleMatches($0.title, normalizedTitle: normalizedTitle) }
      : editionDocs
    return filteredEditions.compactMap { $0.isbn }.flatMap { $0 }
  }

  private static func preferredISBN(from isbns: [String]) -> String? {
    let normalized = isbns.map { normalizedISBN($0) }.filter { !$0.isEmpty }
    if let isbn13 =
      normalized
      .map({ $0.filter(\.isNumber) })
      .first(where: { $0.count == 13 })
    {
      return isbn13
    }
    for isbn in normalized where isbn.count == 10 {
      if let isbn13 = isbn13(fromISBN10: isbn) {
        return isbn13
      }
    }
    return nil
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

  private static func normalizedISBN(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: " ", with: "")
      .uppercased()
  }

  private static func isbn13(fromISBN10 isbn10: String) -> String? {
    let prefix = isbn10.prefix(9)
    guard prefix.allSatisfy({ $0.isNumber }) else { return nil }
    let base = "978" + prefix
    guard let checkDigit = isbn13CheckDigit(for: base) else { return nil }
    return base + checkDigit
  }

  private static func isbn13CheckDigit(for twelveDigits: String) -> String? {
    guard twelveDigits.count == 12,
      twelveDigits.allSatisfy({ $0.isNumber })
    else { return nil }
    var sum = 0
    for (index, char) in twelveDigits.enumerated() {
      guard let digit = char.wholeNumberValue else { return nil }
      sum += (index % 2 == 0) ? digit : digit * 3
    }
    let check = (10 - (sum % 10)) % 10
    return String(check)
  }

}
