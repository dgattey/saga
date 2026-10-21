//
//  BookSearchTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/21/26.
//

import Foundation
import Testing

@testable import Saga

@Suite("Book search engine & tokens")
struct BookSearchTests {
  private func highlightedText(_ excerpt: BookSearchMatch.Excerpt) -> String {
    String(Array(excerpt.text)[excerpt.highlight])
  }

  // MARK: - Engine

  @Test("Review matches anywhere in the full text, well past character 100")
  func reviewMatchPastCharacter100() throws {
    let review =
      String(repeating: "The statues line every wall.\n\n", count: 6)
      + "Beauty is immeasurable; kindness is immeasurable."
    let matchOffset = try #require(review.range(of: "kindness")).lowerBound
    #expect(review.distance(from: review.startIndex, to: matchOffset) > 100)

    let documents = [
      BookSearchDocument(title: "Piranesi", author: "Susanna Clarke", review: review)
    ]
    let hits = BookSearchEngine.search("Kindness is", in: documents)

    #expect(hits.map(\.index) == [0])
    let excerpt = try #require(hits.first?.match.excerpt)
    #expect(excerpt.text == "…Beauty is immeasurable; kindness is immeasurable.")
    #expect(highlightedText(excerpt) == "kindness is")
    #expect(excerpt.source == .review)
  }

  @Test("Private notes match anywhere in the full text and tag excerpts with .notes source")
  func privateNotesMatchAndExcerptSource() throws {
    let notes =
      String(repeating: " margin annotations and page tabs.\n\n", count: 5)
      + "Borrowed from Claire before the trip to Kyoto."
    let documents = [
      BookSearchDocument(
        title: "The Makioka Sisters",
        author: "Jun'ichirō Tanizaki",
        review: "A sweeping family portrait.",
        notes: notes
      )
    ]
    let hits = BookSearchEngine.search("Kyoto", in: documents)

    #expect(hits.map(\.index) == [0])
    let excerpt = try #require(hits.first?.match.excerpt)
    #expect(excerpt.source == .notes)
    #expect(highlightedText(excerpt) == "Kyoto")
    #expect(excerpt.text.contains("trip to Kyoto."))
  }

  @Test("Review excerpts collapse whitespace, snap to words, and add ellipses on both sides")
  func reviewExcerptWindow() throws {
    let review =
      String(repeating: "alpha beta gamma\n", count: 10)
      + "the infinite House\n\n"
      + String(repeating: "delta epsilon zeta ", count: 20)
    let documents = [BookSearchDocument(title: "Piranesi", review: review)]
    let excerpt = try #require(
      BookSearchEngine.search("infinite", in: documents).first?.match.excerpt)

    #expect(excerpt.text.hasPrefix("…"))
    #expect(excerpt.text.hasSuffix("…"))
    #expect(!excerpt.text.contains("\n"))
    #expect(!excerpt.text.contains("  "))
    #expect(highlightedText(excerpt) == "infinite")
    #expect(excerpt.highlight.lowerBound <= 26)
    #expect(excerpt.text.count <= 140)
  }

  @Test("Review matching is case- and diacritic-insensitive")
  func reviewDiacriticInsensitive() {
    let documents = [BookSearchDocument(title: "Kitchen", review: "A CAFÉ at midnight.")]
    let hits = BookSearchEngine.search("cafe", in: documents)
    #expect(hits.count == 1)
    #expect(hits.first?.match.excerpt.map(highlightedText) == "CAFÉ")
  }

  @Test("Titles rank exact, then prefix, then word start, then substring")
  func titleRankingTiers() {
    let documents = [
      BookSearchDocument(title: "The House in the Cerulean Sea"),
      BookSearchDocument(title: "Housekeeping"),
      BookSearchDocument(title: "House"),
      BookSearchDocument(title: "Lighthouse"),
    ]
    let hits = BookSearchEngine.search("house", in: documents)
    #expect(hits.map(\.index) == [2, 1, 0, 3])
    #expect(hits.first?.match.titleRanges == [0..<5])
  }

  @Test("Title matches outrank author matches, which outrank review-only matches")
  func relevanceRanking() {
    let documents = [
      BookSearchDocument(
        title: "Jonathan Strange & Mr Norrell",
        author: "Susanna Clarke",
        review: "The same quiet magic she later distilled into Piranesi."
      ),
      BookSearchDocument(
        title: "The Starless Sea",
        author: "Erin Morgenstern",
        review: "An underground library that feels like a cousin of Piranesi's House."
      ),
      BookSearchDocument(title: "Piranesi", author: "Susanna Clarke"),
      BookSearchDocument(title: "Unrelated", author: "Piranesi Fan Club"),
    ]
    let hits = BookSearchEngine.search("piranesi", in: documents)

    #expect(hits.map(\.index) == [2, 3, 0, 1])
    #expect(hits[0].match.titleRanges == [0..<8])
    #expect(hits[0].match.excerpt == nil)
    #expect(hits[1].match.authorRanges == [0..<8])
    #expect(hits[2].match.excerpt != nil)
    #expect(hits[3].match.excerpt != nil)
  }

  @Test("Every query word can match a word start when the phrase isn't contiguous")
  func multiWordTitleMatch() {
    let documents = [BookSearchDocument(title: "House of Leaves", author: "Mark Z. Danielewski")]
    let hits = BookSearchEngine.search("house leaves", in: documents)
    #expect(hits.first?.match.titleRanges == [0..<5, 9..<15])
  }

  @Test("Titles tolerate typos through the fuzzy fallback")
  func fuzzyTitleMatch() {
    let documents = [
      BookSearchDocument(title: "Piranesi", author: "Susanna Clarke"),
      BookSearchDocument(title: "The Overstory", author: "Richard Powers"),
    ]
    let hits = BookSearchEngine.search("pirnesi", in: documents)
    #expect(hits.map(\.index) == [0])
    #expect(hits.first?.match.titleRanges == [])
  }

  @Test("ISBN matches digits with hyphens and spaces stripped")
  func isbnMatching() {
    let documents = [
      BookSearchDocument(title: "Piranesi", isbn: "9781635575637"),
      BookSearchDocument(title: "Klara and the Sun", isbn: "9780593318171"),
    ]
    #expect(BookSearchEngine.search("978-1-63557", in: documents).map(\.index) == [0])
    #expect(BookSearchEngine.search("1635 5756 37", in: documents).map(\.index) == [0])
    #expect(BookSearchEngine.search("978", in: documents).map(\.index) == [0, 1])
    #expect(BookSearchEngine.search("97", in: documents).isEmpty)
  }

  @Test("Ratings, years, and statuses are not matched as free text")
  func noisyFieldsExcluded() {
    let documents = [
      BookSearchDocument(title: "Piranesi", rating: 5, status: .read, year: 2024)
    ]
    #expect(BookSearchEngine.search("5", in: documents).isEmpty)
    #expect(BookSearchEngine.search("2024", in: documents).isEmpty)
    #expect(BookSearchEngine.search("read", in: documents).isEmpty)
  }

  @Test("An empty query keeps the input order")
  func emptyQueryKeepsOrder() {
    let documents = [
      BookSearchDocument(title: "B"),
      BookSearchDocument(title: "A"),
    ]
    #expect(BookSearchEngine.search("  ", in: documents).map(\.index) == [0, 1])
  }

  // MARK: - Tokens

  @Test("Tokens AND across kinds and OR within a kind")
  func tokenFiltering() {
    let documents = [
      BookSearchDocument(title: "A", review: "Loved it", rating: 5, status: .read, year: 2025),
      BookSearchDocument(
        title: "B", notes: "Private note", rating: 4, status: .read, year: 2024
      ),
      BookSearchDocument(title: "C", rating: 5, status: .reading, year: 2026),
      BookSearchDocument(title: "D", status: .notStarted),
    ]
    func indices(_ tokens: [BookSearchToken], query: String = "") -> [Int] {
      BookSearchEngine.search(query, tokens: tokens, in: documents).map(\.index)
    }

    #expect(indices([.status(.read)]) == [0, 1])
    #expect(indices([.status(.read), .rating(5)]) == [0])
    #expect(indices([.rating(5), .rating(4)]) == [0, 1, 2])
    #expect(indices([.hasReview]) == [0])
    #expect(indices([.hasNotes]) == [1])
    #expect(indices([.year(2026)]) == [2])
    #expect(indices([.status(.notStarted)]) == [3])
    #expect(indices([.status(.read)], query: "b") == [1])
  }

  @Test("Suggestions come from the last typed word and skip applied tokens")
  func tokenSuggestions() {
    let years = [2026, 2025]
    #expect(
      BookSearchToken.suggestions(for: "re", years: years, excluding: [])
        == [.status(.read), .status(.reading), .hasReview])
    #expect(
      BookSearchToken.suggestions(for: "no", years: years, excluding: [])
        == [.hasNotes])
    #expect(
      BookSearchToken.suggestions(for: "priv", years: years, excluding: [])
        == [.hasNotes])
    #expect(BookSearchToken.suggestions(for: "5", years: years, excluding: []) == [.rating(5)])
    #expect(
      BookSearchToken.suggestions(for: "20", years: years, excluding: [])
        == [.year(2026), .year(2025)])
    #expect(
      BookSearchToken.suggestions(for: "house sh", years: years, excluding: [])
        == [.status(.notStarted)])
    #expect(
      BookSearchToken.suggestions(for: "re", years: years, excluding: [.status(.read)])
        == [.status(.reading), .hasReview])
    #expect(BookSearchToken.suggestions(for: "", years: years, excluding: []).isEmpty)
    #expect(BookSearchToken.suggestions(for: "piranesi", years: years, excluding: []).isEmpty)
  }

  @Test("Token labels match the built-in names")
  func tokenLabels() {
    #expect(
      [
        BookSearchToken.status(.reading), .status(.read), .status(.notStarted), .rating(5),
        .hasReview, .hasNotes, .year(2026),
      ].map(\.label)
        == ["Reading", "Read", "On the shelf", "★ 5", "Has review", "Has notes", "2026"])
  }
}
