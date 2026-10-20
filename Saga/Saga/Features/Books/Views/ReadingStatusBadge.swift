//
//  ReadingStatusBadge.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI

extension ReadingStatus {
  /// Shelf names, matching Goodreads.
  var title: String {
    switch self {
    case .notStarted:
      return "Want to Read"
    case .reading:
      return "Currently Reading"
    case .read:
      return "Read"
    }
  }

  /// Compact shelf names for the segmented shelf picker.
  var shortTitle: String {
    switch self {
    case .notStarted:
      return "Want to Read"
    case .reading:
      return "Reading"
    case .read:
      return "Read"
    }
  }

  var systemImage: String {
    switch self {
    case .notStarted:
      return "books.vertical"
    case .reading:
      return "bookmark.fill"
    case .read:
      return "checkmark.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .notStarted:
      return .botanicalGold
    case .reading:
      return .botanicalSage
    case .read:
      return .botanicalLeaf
    }
  }
}

/// A small capsule showing which shelf a book is on.
struct ReadingStatusBadge: View {
  let status: ReadingStatus

  var body: some View {
    Label(status.title, systemImage: status.systemImage)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(status.tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(status.tint.opacity(0.14), in: Capsule())
  }
}
