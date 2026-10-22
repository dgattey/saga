//
//  NowReadingBarView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/21/26.
//

import SwiftUI

/// Floating mini-player bar pinned to the bottom of the Books list showing the active reading book.
struct NowReadingBarView: View {
  private static let cornerRadius: CGFloat = 14
  private static let coverCornerRadius: CGFloat = 6
  private static let coverSize = CGSize(width: 36, height: 54)

  @ObservedObject var book: Book
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        coverThumbnail
        labelsStack
        Spacer(minLength: 8)
        trailingChevron
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .background {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(.regularMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(Color.nowReadingBarFill)
        }
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
    .overlay {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .strokeBorder(Color.nowReadingBarBorder, lineWidth: 0.75)
    }
    .accessibilityIdentifier(AccessibilityID.Books.nowReadingBar)
  }

  private var coverThumbnail: some View {
    BookCoverImageView(book: book, targetSize: Self.coverSize)
      .frame(width: Self.coverSize.width, height: Self.coverSize.height)
      .clipShape(RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous))
      .compositingGroup()
      .shadow(color: .black.opacity(0.16), radius: 3, y: 1.5)
  }

  private var labelsStack: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: "bookmark.fill")
          .font(.system(size: 10, weight: .bold))
          .symbolRenderingMode(.monochrome)
        Text("Currently reading")
          .font(.caption.weight(.semibold))
      }
      .foregroundStyle(Color.nowReadingAccent)

      Text(book.title ?? book.id)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      if let author = book.author, !author.isEmpty {
        Text(author)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private var trailingChevron: some View {
    Image(systemName: "chevron.right")
      .font(.footnote.weight(.semibold))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(.secondary)
      .padding(.trailing, 2)
  }
}
