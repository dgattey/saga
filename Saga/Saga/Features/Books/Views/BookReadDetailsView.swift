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

/// The read-mode title, author, status, metadata, and notes for a book. Empty fields are
/// hidden rather than shown as placeholders.
struct BookReadDetailsView: View {
  @ObservedObject var book: Book

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      header
      if hasMetadata {
        metadataBox
      }
      notes
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(book.title ?? "Untitled book")
        .font(.largeTitleBold)
      if let author = nonEmpty(book.author) {
        Text(author)
          .font(.title2)
          .foregroundStyle(.secondary)
      }
      ReadingStatusBadge(status: book.readingStatus)
        .padding(.top, 4)
    }
  }

  // MARK: - Metadata

  private var rating: Int? {
    guard let value = book.rating?.intValue, (1...5).contains(value) else { return nil }
    return value
  }

  private var readingDuration: String? {
    ReadingDuration.text(started: book.readDateStarted, finished: book.readDateFinished)
  }

  private var isbn: String? { book.isbn?.stringValue }

  private var hasMetadata: Bool {
    rating != nil || book.readDateStarted != nil || book.readDateFinished != nil || isbn != nil
  }

  private var metadataBox: some View {
    GroupBox {
      VStack(spacing: 0) {
        let rows = metadataRows
        ForEach(rows.indices, id: \.self) { index in
          if index > 0 {
            Divider()
          }
          LabeledContent {
            rows[index].value
          } label: {
            Text(rows[index].label)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 6)
        }
      }
    }
  }

  private struct MetadataRow {
    let label: String
    let value: AnyView
  }

  private var metadataRows: [MetadataRow] {
    var rows: [MetadataRow] = []
    if let rating {
      rows.append(
        MetadataRow(
          label: "Rating",
          value: AnyView(
            StarRatingView(rating: rating)
              .accessibilityLabel("\(rating) out of 5 stars")
          )
        )
      )
    }
    if let started = book.readDateStarted {
      rows.append(dateRow("Started", started))
    }
    if let finished = book.readDateFinished {
      rows.append(dateRow("Finished", finished))
    }
    if let readingDuration {
      rows.append(MetadataRow(label: "Reading time", value: AnyView(Text(readingDuration))))
    }
    if let isbn {
      rows.append(
        MetadataRow(label: "ISBN", value: AnyView(Text(isbn).monospacedDigit()))
      )
    }
    return rows
  }

  private func dateRow(_ label: String, _ date: Date) -> MetadataRow {
    MetadataRow(
      label: label,
      value: AnyView(Text(date.formatted(date: .abbreviated, time: .omitted)))
    )
  }

  // MARK: - Notes

  @ViewBuilder
  private var notes: some View {
    if let review = book.reviewDescription,
      !review.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let attributedString = review.attributedString
    {
      VStack(alignment: .leading, spacing: 8) {
        Text("Notes")
          .font(.headline)
        AttributedTextViewer(attributedString: attributedString)
      }
    }
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
