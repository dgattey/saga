//
//  BookEditorialLayout.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI

/// Shared measurements for the book page, so read mode, edit mode, and new books line up exactly.
enum BookEditorialMetrics {
  static let coverWidth: CGFloat = 190
  static let coverSize = CGSize(
    width: coverWidth,
    height: coverWidth / BookCoverImageView.coverAspectRatio
  )
  static let coverCornerRadius: CGFloat = 6
  static let columnGap: CGFloat = 40
  static let outsidePadding: CGFloat = 32
  static let maxDetailsWidth: CGFloat = 560
  /// Below this width the cover stacks above the details.
  static let twoColumnThreshold: CGFloat = 600
  /// Horizontal inset of editable fields. Fields are pulled out by the same amount so their text
  /// sits exactly where the read-mode text was.
  static let fieldInset: CGFloat = 8
}

/// The book page: cover on the left, details on the right, stacking on narrow widths. Read mode,
/// edit mode, and new books all use it so nothing jumps when editing starts.
struct BookEditorialLayout<Cover: View, Details: View>: View {
  private let scrollScope: ScrollScope?
  private let scrollContextID: UUID?
  private let cover: Cover
  private let details: Details

  init(
    scrollScope: ScrollScope? = nil,
    scrollContextID: UUID? = nil,
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder details: () -> Details
  ) {
    self.scrollScope = scrollScope
    self.scrollContextID = scrollContextID
    self.cover = cover()
    self.details = details()
  }

  var body: some View {
    MeasuredContainer { size in
      scrollView {
        Group {
          if size.width == 0 || size.width >= BookEditorialMetrics.twoColumnThreshold {
            HStack(alignment: .top, spacing: BookEditorialMetrics.columnGap) {
              cover
              details
                .frame(maxWidth: BookEditorialMetrics.maxDetailsWidth, alignment: .topLeading)
            }
          } else {
            VStack(alignment: .leading, spacing: 28) {
              cover
                .frame(maxWidth: .infinity)
              details
            }
          }
        }
        .padding(BookEditorialMetrics.outsidePadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .scrollEdgeEffectStyle(.soft, for: .top)
    }
  }

  @ViewBuilder
  private func scrollView<Content: View>(@ViewBuilder content: @escaping () -> Content)
    -> some View
  {
    if let scrollScope {
      PersistentScrollView(
        scrollKey: ScrollKey(scope: scrollScope, region: "page", contextID: scrollContextID)
      ) {
        content()
      }
    } else {
      ScrollView(.vertical) {
        content()
      }
    }
  }
}

// MARK: - Labels & metadata

/// An uppercase caption used above metadata values and section content.
struct EditorialSectionLabel: View {
  private let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text.uppercased())
      .font(.editorialLabel)
      .tracking(0.8)
      .foregroundStyle(.secondary)
  }
}

/// A label stacked above its value or control, e.g. "STARTED" over "Feb 2, 2026".
struct EditorialLabeledValue<Value: View>: View {
  let label: String
  @ViewBuilder let value: Value

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      EditorialSectionLabel(label)
      value
    }
  }
}

/// One label/value pair in a book's read-mode metadata strip.
struct BookMetadataEntry: Identifiable, Equatable {
  let label: String
  let value: String

  var id: String { label }
}

/// Read-mode metadata in one row with hairlines between values. On narrower panes it wraps into
/// rows of two, then a single column.
struct BookMetadataStrip: View {
  let entries: [BookMetadataEntry]

  var body: some View {
    ViewThatFits(in: .horizontal) {
      EditorialHairlineRow(count: entries.count) { index in
        value(for: entries[index])
      }
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { start in
          let pair = Array(entries[start..<min(start + 2, entries.count)])
          EditorialHairlineRow(count: pair.count) { index in
            value(for: pair[index])
          }
        }
      }
      VStack(alignment: .leading, spacing: 14) {
        ForEach(entries) { entry in
          value(for: entry)
        }
      }
    }
  }

  private func value(for entry: BookMetadataEntry) -> some View {
    EditorialLabeledValue(label: entry.label) {
      Text(entry.value)
        .font(.callout.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
    }
  }
}

/// Lays items out in a row separated by thin vertical hairlines.
struct EditorialHairlineRow<Item: View>: View {
  static var spacing: CGFloat { 16 }

  let count: Int
  @ViewBuilder let item: (Int) -> Item

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(0..<count, id: \.self) { index in
        if index > 0 {
          Divider()
            .frame(height: 34)
        }
        item(index)
          .padding(.leading, index == 0 ? 0 : Self.spacing)
          .padding(.trailing, index == count - 1 ? 0 : Self.spacing)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

// MARK: - Editable fields

extension View {
  /// Styles a text field so it reads as the same text it replaces in read mode, in a soft
  /// rounded well that picks up a botanical ring when focused.
  func editorialField(isFocused: Bool) -> some View {
    modifier(EditorialFieldModifier(isFocused: isFocused))
  }
}

private struct EditorialFieldModifier: ViewModifier {
  let isFocused: Bool

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    content
      .textFieldStyle(.plain)
      .padding(.horizontal, BookEditorialMetrics.fieldInset)
      .padding(.vertical, 4)
      .background(shape.fill(Color.primary.opacity(isFocused ? 0.03 : 0.055)))
      .overlay(
        shape.strokeBorder(Color.botanicalLeaf.opacity(isFocused ? 0.85 : 0), lineWidth: 1.5)
      )
      .padding(.horizontal, -BookEditorialMetrics.fieldInset)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }
}
