//
//  CoverImageResolver.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Foundation

/// The default "best cover" pipeline (originally built for the Goodreads CSV import): checks
/// OpenLibrary by ISBN and title/author, falls back to BookcoverAPI when OpenLibrary only has a
/// small image, and picks the larger, higher quality candidate.
enum CoverImageResolver {
  enum Selection {
    static let openLibraryPreferBookcoverBelowBytes = 80_000
    static let bookcoverPreferredMinBytes = 30_000
    static let bookcoverPreferredRatio = 0.85
  }

  private static let cache = CoverImageURLCache()

  /// Returns the best cover image URL for a book, or `nil` if no candidate is found.
  static func bestCoverURL(isbn: String?, title: String, author: String) async -> String? {
    guard !PersistenceService.isRunningUnitTests else { return nil }
    let normalizedTitle = title.cleanedWhitespace
    let normalizedAuthor = author.cleanedWhitespace
    guard let isbn = isbn?.cleanedWhitespace, !isbn.isEmpty else {
      guard !normalizedTitle.isEmpty else { return nil }
      return try? await OpenLibraryAPIService.coverImageURL(
        forTitle: normalizedTitle,
        author: normalizedAuthor
      )
    }
    return await cache.value(forISBN: isbn) {
      do {
        let openLibraryCandidate = try await OpenLibraryAPIService.bestCoverCandidate(
          forISBN: isbn,
          title: normalizedTitle,
          author: normalizedAuthor
        )
        let shouldCheckBookcover =
          (openLibraryCandidate?.bytes ?? 0) < Selection.openLibraryPreferBookcoverBelowBytes
        let bookcoverCandidate =
          shouldCheckBookcover
          ? try await BookcoverAPIService.coverImageCandidate(forISBN: isbn)
          : nil
        return preferredCandidate(openLibrary: openLibraryCandidate, bookcover: bookcoverCandidate)?
          .url
      } catch {
        LoggerService.log(
          "Cover lookup failed for ISBN \(isbn)",
          error: error,
          surface: .network
        )
        return nil
      }
    }
  }

  /// Prefers BookcoverAPI (Goodreads) art when it's reasonably large relative to OpenLibrary,
  /// otherwise the larger of the two.
  static func preferredCandidate(
    openLibrary: CoverImageCandidate?,
    bookcover: CoverImageCandidate?
  ) -> CoverImageCandidate? {
    guard let openLibrary else { return bookcover }
    guard let bookcover else { return openLibrary }
    if bookcover.bytes >= Selection.bookcoverPreferredMinBytes,
      Double(bookcover.bytes) >= Double(openLibrary.bytes) * Selection.bookcoverPreferredRatio
    {
      return bookcover
    }
    return openLibrary.bytes >= bookcover.bytes ? openLibrary : bookcover
  }
}

/// Deduplicates concurrent lookups per ISBN and caches found URLs. Misses aren't cached so a
/// later search can retry after a network failure.
private actor CoverImageURLCache {
  private var values: [String: String] = [:]
  private var tasks: [String: Task<String?, Never>] = [:]

  func value(forISBN isbn: String, fetch: @escaping @Sendable () async -> String?) async -> String?
  {
    if let cached = values[isbn] {
      return cached
    }
    if let existingTask = tasks[isbn] {
      return await existingTask.value
    }
    let task = Task { await fetch() }
    tasks[isbn] = task
    let value = await task.value
    tasks[isbn] = nil
    values[isbn] = value
    return value
  }
}
