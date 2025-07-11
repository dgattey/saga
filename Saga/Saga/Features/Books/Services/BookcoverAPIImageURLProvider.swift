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
    /// Maximum concurrent image requests
    static let maxConcurrentRequests: Int = 15
}

/// Provides methods for getting an image cover URL for an ISBN from the Bookcover API.
/// The API fetches from Goodreads to find the underlying image URL.
struct BookcoverAPIImageURLProvider: CoverImageURLProvider {
    
    /// Uses the bookcover API to fetch a specific ISBN's cover image URL (in response)
    private struct CoverImageResponse: Decodable {
        let url: String
    }
    
    private init() {}

    /// Fetches from network one cover image URL
    static func url(forISBN isbn: String) async throws -> String? {
        guard let url = URL(string: "\(Constants.apiBaseURL)/\(isbn)") else {
            return nil
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        // Decode the JSON response
        guard let coverImageResponse = try? JSONDecoder().decode(CoverImageResponse.self, from: data) else {
            return nil
        }
        return coverImageResponse.url
    }

    /// Fetches a group of cover images using a maximum amount of concurrent requests for safety
    static func urls(forISBNs isbns: [String]) async -> [String: String?] {
        var results = [String: String?]()
        var index = 0
        while index < isbns.count {
            let batch = Array(isbns[index..<min(index + Constants.maxConcurrentRequests, isbns.count)])
            await withTaskGroup(of: (String, String?).self) { group in
                for isbn in batch {
                    group.addTask {
                        let url = try? await url(forISBN: isbn)
                        return (isbn, url)
                    }
                }
                for await (isbn, url) in group {
                    results[isbn] = url
                }
            }
            index += Constants.maxConcurrentRequests
        }
        return results
    }
}
