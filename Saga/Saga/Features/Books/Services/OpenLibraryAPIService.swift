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
}

private struct SearchResponse: Decodable {
    let docs: [Doc]?
}

private struct Doc: Decodable {
    let key: String?
    let language: [String]?
    let editions: Editions?
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
    
    /// Generates a URL without network call, using the large size, ensuring it's not a 404 image
    static func coverImageURL(forISBN isbn: String) async throws -> String? {
        guard let url = URL(string: "\(Constants.coverImagesBaseURL)/b/isbn/\(isbn)-L.jpg?default=false") else {
            return nil
        }
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode != 404 else {
            return nil
        }
        return url.absoluteString
    }
    
    /// Fetches an ISBN for a given title/author combo, using the search and editions APIs
    static func isbnFor(title: String, author: String) async throws -> String? {
        let searchResponse = try await searchResponse(forTitle: title, author: author)
        guard let response = searchResponse,
              let docs = response.docs, !docs.isEmpty else {
            print("Error: failed to fetch search: \(searchResponse.debugDescription)")
            return nil
        }
        
        // Find the first work that includes English ("eng") in its language array and has some ISBNs, or fetch them
        let englishDocs = docs.filter { $0.language?.contains("eng") == true }
        let docsWithISBNs = englishDocs.filter { $0.editions?.docs?.contains(where: { $0.isbn?.count ?? 0 > 0 }) ?? false }
        let isbns: [String]
        if let presentISBNs = docsWithISBNs.first?.editions?.docs?.first?.isbn,
           !presentISBNs.isEmpty {
            isbns = presentISBNs
        } else if let workKey = englishDocs.first?.key,
                  let isbnsFromEditions = try await fetchISBNsFromEditions(forWorkKey: workKey, title: title),
                  !isbnsFromEditions.isEmpty {
            isbns = isbnsFromEditions
        } else {
            print("Warning: missing ISBNs for \"\(title)\"")
            return nil
        }
        
        // Parse out the longest ISBN so we get the 13 digit if possible
        guard let isbn = isbns.sorted(by: { isbn1, isbn2 in
                  isbn1.count > isbn2.count
              }).first else {
            print("Error: somehow still missing an isbn for \"\(title)\"")
            return nil
        }
        
        // Important to log
        if isbn.count < 13 {
            print("Warning: didn't find a 13-digit ISBN for \"\(title)\"")
        }
        return isbn
    }
    
    /// Sometimes the search endpoint doesn't return an edition with an ISBN, for whatever reason. This fetches a work specifically to find its ISBN
    /// to fix that problem in limited cases with an extra fetch.
    private static func fetchISBNsFromEditions(forWorkKey workKey: String, title: String) async throws -> [String]? {
        let editionsResponse = try await editionsResponse(forWorkKey: workKey, title: title)
        guard let response = editionsResponse,
              let editions = response.entries,
              !editions.isEmpty else {
            print("Error: empty editions response")
            return nil
        }
        for edition in editions {
            if let langs = edition.languages,
               langs.contains(where: { $0.key == "/languages/eng" }) {
                return edition.isbn
            }
        }
        print("Error: editions didn't include an isbn for \(title): \(editions)\n")
        return nil
    }
    
    /// Fetches the search response for a title/author combo, pulling in the title/isbn from the attached editions.
    private static func searchResponse(forTitle title: String, author: String) async throws -> SearchResponse? {
        guard var components = URLComponents(string: "\(Constants.apiBaseURL)/search.json") else {
            return nil
        }
        // Removes series info from titles like "Death's End (Three body problem #3)" for better searching
        let cleanedTitle = title.replacingOccurrences(
            of: #" \([^(#)]*#\d+\)$"#,
            with: "",
            options: .regularExpression
        )
        let query = "\(cleanedTitle) \(author)"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "key,language,editions,editions.title,editions.isbn"),
            URLQueryItem(name: "lang", value: "en"),
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Couldn't fetch search response for \"\(title)\": \(response)")
            return nil
        }
        return try? JSONDecoder().decode(SearchResponse.self, from: data)
    }
    
    /// Fetches the editions response for a given work key
    private static func editionsResponse(forWorkKey workKey: String, title: String) async throws -> EditionsResponse? {
        let editionsURLString = "\(Constants.apiBaseURL)\(workKey)/editions.json"
        guard let editionsURL = URL(string: editionsURLString) else { return nil }
        
        let (data, response) = try await URLSession.shared.data(from: editionsURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Couldn't fetch editions response for \"\(title)\": \(response)")
            return nil
        }
        return try? JSONDecoder().decode(EditionsResponse.self, from: data)
    }
    
     
}
