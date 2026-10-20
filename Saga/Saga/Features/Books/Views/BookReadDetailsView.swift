//
//  BookReadDetailsView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI

/// Formats how long a book took (or has taken so far) to read.
enum ReadingDuration {
  static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
    let components = calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: start),
      to: calendar.startOfDay(for: end)
    )
    return max(0, components.day ?? 0)
  }

  /// `nil` when there's no start date to measure from.
  static func text(
    started: Date?,
    finished: Date?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String? {
    guard let started else { return nil }
    let isFinished = finished != nil
    let days = days(from: started, to: finished ?? now, calendar: calendar)
    switch days {
    case 0:
      return isFinished ? "Finished the same day" : "Started today"
    case 1:
      return isFinished ? "1 day" : "1 day so far"
    default:
      return isFinished ? "\(days) days" : "\(days) days so far"
    }
  }
}

/// The read-mode details column: serif title, author, shelf and rating, a horizontal metadata
/// strip, and borderless editorial notes. Empty metadata is hidden rather than shown as blanks.
struct BookReadDetailsView: View {
  @ObservedObject var book: Book

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      let entries = Self.metadataEntries(for: book)
      if !entries.isEmpty {
        BookMetadataStrip(entries: entries)
          .padding(.top, 22)
      }
      Divider()
        .padding(.vertical, 22)
      notes
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(book.title ?? "Untitled book")
        .font(.editorialTitle)
        .fixedSize(horizontal: false, vertical: true)
      if let author = book.author?.cleanedWhitespace, !author.isEmpty {
        Text(author)
          .font(.editorialAuthor)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        ReadingStatusBadge(status: book.readingStatus)
        if let rating = Self.rating(for: book) {
          StarRatingView(rating: rating, size: 15)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rating) out of 5 stars")
        }
      }
      .padding(.top, 10)
    }
  }

  // MARK: - Notes

  @ViewBuilder
  private var notes: some View {
    if let review = book.reviewDescription,
      !review.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      VStack(alignment: .leading, spacing: 10) {
        EditorialSectionLabel("Notes")
        AttributedTextViewer(attributedString: review.editorialAttributedString())
      }
    } else {
      BookNotesEmptyState()
    }
  }

  // MARK: - Derived values

  static func rating(for book: Book) -> Int? {
    guard let value = book.rating?.intValue, (1...5).contains(value) else { return nil }
    return value
  }

  /// Started · Finished · Duration · ISBN, skipping anything the book doesn't have.
  static func metadataEntries(for book: Book, now: Date = Date()) -> [BookMetadataEntry] {
    var entries: [BookMetadataEntry] = []
    if let started = book.readDateStarted {
      entries.append(BookMetadataEntry(label: "Started", value: formatted(started)))
    }
    if let finished = book.readDateFinished {
      entries.append(BookMetadataEntry(label: "Finished", value: formatted(finished)))
    }
    if let duration = ReadingDuration.text(
      started: book.readDateStarted,
      finished: book.readDateFinished,
      now: now
    ) {
      entries.append(BookMetadataEntry(label: "Duration", value: duration))
    }
    if let isbn = book.isbn?.stringValue {
      entries.append(BookMetadataEntry(label: "ISBN", value: isbn))
    }
    return entries
  }

  private static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
  }
}

/// Shown in place of notes when a book doesn't have any yet.
struct BookNotesEmptyState: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      EditorialSectionLabel("Notes")
      Text("No notes yet. Choose Edit to add your thoughts.")
        .font(.editorialNotes.italic())
        .foregroundStyle(.tertiary)
    }
  }
}
