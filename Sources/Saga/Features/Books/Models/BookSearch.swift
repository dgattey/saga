//
//  BookSearch.swift
//  Saga
//
//  Created by Dylan Gattey on 10/21/26.
//

import Foundation
import Ifrit

/// A built-in filter derived from fields every book already has.
enum BookSearchToken: Hashable, Identifiable, Sendable {
  case status(ReadingStatus)
  case rating(Int)
  case hasReview
  case hasNotes
  case year(Int)

  enum Kind: Hashable {
    case status
    case rating
    case hasReview
    case hasNotes
    case year
  }

  var id: Self { self }

  var kind: Kind {
    switch self {
    case .status: .status
    case .rating: .rating
    case .hasReview: .hasReview
    case .hasNotes: .hasNotes
    case .year: .year
    }
  }

  var label: String {
    switch self {
    case .status(.read): "Read"
    case .status(.reading): "Reading"
    case .status(.notStarted): "On the shelf"
    case .rating(let stars): "★ \(stars)"
    case .hasReview: "Has review"
    case .hasNotes: "Has notes"
    case .year(let year): String(year)
    }
  }

  var systemImage: String {
    switch self {
    case .status(.read): "checkmark.circle"
    case .status(.reading): "bookmark"
    case .status(.notStarted): "books.vertical"
    case .rating: "star"
    case .hasReview: "text.quote"
    case .hasNotes: "lock.doc"
    case .year: "calendar"
    }
  }

  func matches(_ document: BookSearchDocument) -> Bool {
    switch self {
    case .status(let status): document.status == status
    case .rating(let stars): document.rating == stars
    case .hasReview: !document.review.isEmpty
    case .hasNotes: !document.notes.isEmpty
    case .year(let year): document.year == year
    }
  }

  private var keywords: [String] {
    switch self {
    case .status(.read): ["read", "finished"]
    case .status(.reading): ["reading", "current"]
    case .status(.notStarted): ["shelf", "unread", "want"]
    case .rating(let stars): ["\(stars)", "★\(stars)"]
    case .hasReview: ["review"]
    case .hasNotes: ["notes", "private"]
    case .year(let year): [String(year)]
    }
  }

  /// Tokens whose keywords start with the last word typed, skipping any already applied.
  static func suggestions(
    for text: String,
    years: [Int],
    excluding activeTokens: [BookSearchToken]
  ) -> [BookSearchToken] {
    guard let fragment = text.split(whereSeparator: \.isWhitespace).last?.lowercased() else {
      return []
    }
    let candidates: [BookSearchToken] =
      [.status(.read), .status(.reading), .status(.notStarted)]
      + (1...5).reversed().map { .rating($0) }
      + [.hasReview, .hasNotes]
      + years.map { .year($0) }
    return candidates.filter { token in
      !activeTokens.contains(token) && token.keywords.contains { $0.hasPrefix(fragment) }
    }
  }
}

/// A `Sendable` snapshot of the book fields that search and token filtering read.
struct BookSearchDocument: Equatable, Sendable {
  var title = ""
  var author = ""
  var isbn = ""
  var review = ""
  var notes = ""
  var rating: Int?
  var status = ReadingStatus.notStarted
  var year: Int?
}

/// Why a book matched, as character offsets into the matched strings.
struct BookSearchMatch: Equatable, Sendable {
  struct Excerpt: Equatable, Sendable {
    enum Source: Equatable, Sendable {
      case review
      case notes
    }

    let text: String
    let highlight: Range<Int>
    var source: Source = .review
  }

  var score: Double = 0
  var titleRanges: [Range<Int>] = []
  var authorRanges: [Range<Int>] = []
  /// Present only when the query matched the review or private notes and nothing else.
  var excerpt: Excerpt?
}

struct BookSearchHit: Equatable, Sendable {
  let index: Int
  let match: BookSearchMatch
}

/// Local, relevance-ranked search across titles, authors, ISBNs, and full review text.
enum BookSearchEngine {
  private struct FieldMatch {
    let quality: Double
    let ranges: [Range<String.Index>]
  }

  private static let fuse = Fuse(threshold: 0.35)
  private static let compareOptions: String.CompareOptions = [
    .caseInsensitive, .diacriticInsensitive,
  ]
  /// Excerpts are one tail-truncated line, so the match sits near the start to survive narrow rows.
  private static let excerptLeadingContext = 24
  private static let excerptContext = 120

  /// Filters `documents` by `tokens` (AND across kinds, OR within a kind), then ranks matches for
  /// `query`. An empty query keeps the input order.
  static func search(
    _ query: String,
    tokens: [BookSearchToken] = [],
    in documents: [BookSearchDocument]
  ) -> [BookSearchHit] {
    let tokenGroups = Array(Dictionary(grouping: tokens, by: \.kind).values)
    let candidates = documents.indices.filter { index in
      tokenGroups.allSatisfy { group in group.contains { $0.matches(documents[index]) } }
    }
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return candidates.map { BookSearchHit(index: $0, match: BookSearchMatch()) }
    }

    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    let pattern = (3...32).contains(query.count) ? fuse.createPattern(from: query) : nil
    return
      candidates
      .compactMap { index in
        match(query, words: words, pattern: pattern, in: documents[index]).map {
          BookSearchHit(index: index, match: $0)
        }
      }
      .sorted { lhs, rhs in
        lhs.match.score == rhs.match.score
          ? lhs.index < rhs.index : lhs.match.score > rhs.match.score
      }
  }

  private static func match(
    _ query: String,
    words: [String],
    pattern: Fuse.Pattern?,
    in document: BookSearchDocument
  ) -> BookSearchMatch? {
    let title = textMatch(query, words: words, in: document.title)
    let author = textMatch(query, words: words, in: document.author)
    let fieldScores = [
      title.map { $0.quality } ?? fuzzyQuality(pattern, in: document.title),
      (author.map { $0.quality } ?? fuzzyQuality(pattern, in: document.author)) * 0.85,
      isbnQuality(query, in: document.isbn) * 0.9,
    ]
    let bestFieldScore = fieldScores.max() ?? 0
    if bestFieldScore > 0 {
      return BookSearchMatch(
        score: bestFieldScore,
        titleRanges: offsets(of: title?.ranges ?? [], in: document.title),
        authorRanges: offsets(of: author?.ranges ?? [], in: document.author)
      )
    }

    let reviewMatch = textMatch(query, words: words, in: document.review)
    let notesMatch = textMatch(query, words: words, in: document.notes)
    if let notes = notesMatch,
      let firstRange = notes.ranges.first,
      notes.quality > (reviewMatch?.quality ?? 0)
    {
      return BookSearchMatch(
        score: notes.quality * 0.65,
        excerpt: excerpt(of: document.notes, around: firstRange, source: .notes)
      )
    }
    guard let review = reviewMatch,
      let firstRange = review.ranges.first
    else {
      return nil
    }
    return BookSearchMatch(
      score: review.quality * 0.65,
      excerpt: excerpt(of: document.review, around: firstRange, source: .review)
    )
  }

  /// Exact, prefix, word-start, or substring match anywhere in `field`, falling back to every
  /// query word starting a word somewhere in `field`.
  private static func textMatch(_ query: String, words: [String], in field: String)
    -> FieldMatch?
  {
    guard !field.isEmpty else { return nil }
    if let range = wordStartRange(of: query, in: field) {
      let quality: Double
      if range == field.startIndex..<field.endIndex {
        quality = 1
      } else if range.lowerBound == field.startIndex {
        quality = 0.95
      } else {
        quality = 0.9
      }
      return FieldMatch(quality: quality, ranges: [range])
    }
    if let range = field.range(of: query, options: compareOptions) {
      return FieldMatch(quality: 0.8, ranges: [range])
    }
    guard words.count > 1 else { return nil }
    var ranges: [Range<String.Index>] = []
    for word in words {
      guard let range = wordStartRange(of: word, in: field) else { return nil }
      ranges.append(range)
    }
    return FieldMatch(quality: 0.75, ranges: ranges)
  }

  private static func wordStartRange(of term: String, in field: String) -> Range<String.Index>? {
    var searchStart = field.startIndex
    while searchStart < field.endIndex,
      let range = field.range(
        of: term, options: compareOptions, range: searchStart..<field.endIndex)
    {
      if range.lowerBound == field.startIndex {
        return range
      }
      let previous = field[field.index(before: range.lowerBound)]
      if !previous.isLetter && !previous.isNumber {
        return range
      }
      searchStart = field.index(after: range.lowerBound)
    }
    return nil
  }

  /// Typo-tolerant fallback for short fields; scaled below every exact match.
  private static func fuzzyQuality(_ pattern: Fuse.Pattern?, in field: String) -> Double {
    guard !field.isEmpty, let result = fuse.search(pattern, in: field) else { return 0 }
    return (1 - result.score) * 0.6
  }

  private static func isbnQuality(_ query: String, in isbn: String) -> Double {
    guard !isbn.isEmpty,
      query.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " })
    else {
      return 0
    }
    let digits = query.filter(\.isNumber)
    guard digits.count >= 3 else { return 0 }
    if isbn.hasPrefix(digits) {
      return 1
    }
    return isbn.contains(digits) ? 0.9 : 0
  }

  private static func offsets(of ranges: [Range<String.Index>], in field: String) -> [Range<Int>] {
    ranges.map { range in
      let start = field.distance(from: field.startIndex, to: range.lowerBound)
      return start..<(start + field.distance(from: range.lowerBound, to: range.upperBound))
    }
  }

  /// About `excerptContext` characters of review or notes around the match, snapped to word
  /// boundaries with whitespace collapsed.
  private static func excerpt(
    of text: String,
    around range: Range<String.Index>,
    source: BookSearchMatch.Excerpt.Source = .review
  ) -> BookSearchMatch.Excerpt {
    var lower =
      text.index(range.lowerBound, offsetBy: -excerptLeadingContext, limitedBy: text.startIndex)
      ?? text.startIndex
    let trailingContext = excerptContext - text.distance(from: lower, to: range.lowerBound)
    var upper =
      text.index(range.upperBound, offsetBy: trailingContext, limitedBy: text.endIndex)
      ?? text.endIndex
    if lower > text.startIndex, !text[text.index(before: lower)].isWhitespace,
      let space = text[lower..<range.lowerBound].firstIndex(where: \.isWhitespace)
    {
      lower = text.index(after: space)
    }
    if upper < text.endIndex, !text[upper].isWhitespace,
      let space = text[range.upperBound..<upper].lastIndex(where: \.isWhitespace)
    {
      upper = space
    }

    let leading = String(collapsingWhitespace(text[lower..<range.lowerBound]).drop { $0 == " " })
    let matched = collapsingWhitespace(text[range])
    var trailing = collapsingWhitespace(text[range.upperBound..<upper])
    while trailing.last == " " {
      trailing.removeLast()
    }
    let prefix = (lower > text.startIndex ? "…" : "") + leading
    let suffix = upper < text.endIndex ? "…" : ""
    return BookSearchMatch.Excerpt(
      text: prefix + matched + trailing + suffix,
      highlight: prefix.count..<(prefix.count + matched.count),
      source: source
    )
  }

  private static func collapsingWhitespace(_ text: Substring) -> String {
    var result = ""
    for character in text {
      if character.isWhitespace {
        if result.last != " " {
          result.append(" ")
        }
      } else {
        result.append(character)
      }
    }
    return result
  }
}
