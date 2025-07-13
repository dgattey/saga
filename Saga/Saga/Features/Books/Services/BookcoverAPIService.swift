//
//  BookcoverAPIImageURLProvider.swift
//  Saga
//
//  Created by Dylan Gattey on 7/10/25.
//

import Foundation

private struct Constants {
    /// API for fetching cover images
    static let apiBaseURL = "https://bookcover.longitood.com/bookcover"
}

/// Corresponds to the cover image URL response
private struct CoverImageURLResponse: Decodable {
    let url: String
}

/// Provides methods for working with the BookcoverAPI service
struct BookcoverAPIService: CoverImageURLProvider {
    
    private init() {}

    /// Fetches one cover image URL from the BookcoverAPI, which uses Goodreads API under the hood
    static func coverImageURL(forISBN isbn: String) async throws -> String? {
        guard let url = URL(string: "\(Constants.apiBaseURL)/\(isbn)") else {
            return nil
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        // Decode the JSON response
        guard let coverImageResponse = try? JSONDecoder().decode(CoverImageURLResponse.self, from: data) else {
            return nil
        }
        return coverImageResponse.url
    }
}
