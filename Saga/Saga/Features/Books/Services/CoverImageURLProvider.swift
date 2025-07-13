//
//  CoverImageURLProvider.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

/// Every provider that provides cover image URLs must conform to this
protocol CoverImageURLProvider {
    
    /// Grabs a cover image URL by some means for a given ISBN. May return nil
    static func coverImageURL(forISBN isbn: String) async throws -> String?
}
