//
//  HomeBooksSectionView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

private struct Constants {
  static let outsidePadding: CGFloat = 32
  static let gridSpacing: CGFloat = 16
  static let minItemWidth: CGFloat = 140
  static let maxItemWidth: CGFloat = 220
}

/// Renders the books section in the Home view
struct HomeBooksSectionView: View {
  @EnvironmentObject private var viewModel: BooksViewModel
  @Binding var entry: NavigationEntry?
  @State private var gridWidth: CGFloat = 0

  private var columns: [GridItem] {
    [
      GridItem(
        .adaptive(
          minimum: Constants.minItemWidth,
          maximum: Constants.maxItemWidth
        ),
        spacing: Constants.gridSpacing,
        alignment: .top
      )
    ]
  }

  var body: some View {
    LazyVGrid(
      columns: columns,
      alignment: .leading,
      spacing: Constants.gridSpacing
    ) {
      if viewModel.filteredBooks.isEmpty, hasActiveSearch {
        Text("No results")
          .font(.headline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else {
        ForEach(viewModel.filteredBooks, id: \.model.objectID) { result in
          HomeBookThumbnailView(
            book: result.model,
            entry: $entry,
            gridItemSize: gridItemSize
          )
        }
      }
    }
    .padding(.horizontal, Constants.outsidePadding)
    .padding(.bottom, Constants.outsidePadding)
    .readSize { size in
      if size.width != gridWidth {
        gridWidth = size.width
      }
    }
  }

  private var hasActiveSearch: Bool {
    !viewModel.searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var gridItemSize: CGSize {
    let width = gridItemWidth
    return CGSize(
      width: width,
      height: width / BookCoverImageView.coverAspectRatio
    )
  }

  private var gridItemWidth: CGFloat {
    let availableWidth = max(
      gridWidth - (Constants.outsidePadding * 2),
      Constants.minItemWidth
    )
    let rawCount =
      (availableWidth + Constants.gridSpacing) / (Constants.minItemWidth + Constants.gridSpacing)
    let columnCount = max(1, Int(floor(rawCount)))
    let totalSpacing = CGFloat(columnCount - 1) * Constants.gridSpacing
    let width = (availableWidth - totalSpacing) / CGFloat(columnCount)
    return min(Constants.maxItemWidth, max(Constants.minItemWidth, width))
  }
}

/// Renders a single book thumbnail for the Home grid
struct HomeBookThumbnailView: View {
  @Environment(\.coverNamespace) private var coverNamespace
  @EnvironmentObject private var animationSettings: AnimationSettings
  let book: Book
  @Binding var entry: NavigationEntry?
  let gridItemSize: CGSize

  var body: some View {
    Button {
      guard entry?.selection != .book(book.objectID) else { return }
      withAnimation(animationSettings.selectionSpring) {
        entry = NavigationEntry(selection: .book(book.objectID))
      }
    } label: {
      coverImageView
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var coverImageView: some View {
    if let coverNamespace {
      coverImageBase
        .matchedGeometryEffect(id: coverID, in: coverNamespace)
    } else {
      coverImageBase
    }
  }

  private var coverImageBase: some View {
    BookCoverImageView(book: book, targetSize: gridItemSize)
      .frame(width: gridItemSize.width, height: gridItemSize.height)
      .defaultShadow()
  }

  private var coverID: String {
    book.objectID.uriRepresentation().absoluteString
  }
}
