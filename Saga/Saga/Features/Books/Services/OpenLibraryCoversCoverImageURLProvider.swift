//
//  OpenLibraryCoversCoverImageURLProvider.swift
//  Saga
//
//  Created by Dylan Gattey on 7/11/25.
//

struct OpenLibraryCoversCoverImageURLProvider: CoverImageURLProvider {
    
    private init() {}
    
    /// Generates a URL without network call, using the large size
    static func url(forISBN isbn: String) async throws -> String? {
        return "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg"
    }
}
