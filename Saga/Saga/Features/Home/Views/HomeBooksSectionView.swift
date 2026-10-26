//
//  HomeBooksSectionView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import CoreData
import SwiftUI

private struct Constants {
  static let outsidePadding: CGFloat = 32
  static let gridSpacing: CGFloat = 16
  static let minItemWidth: CGFloat = 140
  static let maxItemWidth: CGFloat = 220
}

/// Renders the books section in the Home view
struct HomeBooksSectionView: View {
  @Environment(BooksViewModel.self) private var viewModel
  @Binding var entry: NavigationEntry?
  var sort: HomeBookSort = .defaultOrder
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
      if viewModel.filteredBooks.isEmpty, viewModel.hasActiveSearch {
        Text("No results")
          .font(.headline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else if sort.isGrouped {
        ForEach(groupedSections) { group in
          Section {
            ForEach(group.books, id: \.book.objectID) { result in
              HomeBookThumbnailView(
                book: result.book,
                gridItemSize: gridItemSize,
                onSelect: selectBook
              )
            }
          } header: {
            HomeBookGroupHeaderView(group: group)
          }
        }
      } else {
        ForEach(sortedBooks, id: \.book.objectID) { result in
          HomeBookThumbnailView(
            book: result.book,
            gridItemSize: gridItemSize,
            onSelect: selectBook
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

  private var sortedBooks: [BookSearchResult] {
    if sort == .defaultOrder && viewModel.hasActiveSearch && !viewModel.searchModel.query.isEmpty {
      return viewModel.filteredBooks
    }
    return sort.sortedResults(from: viewModel.filteredBooks)
  }

  private var groupedSections: [HomeBookGroup] {
    sort.groups(from: viewModel.filteredBooks)
  }

  private func selectBook(_ bookID: NSManagedObjectID) {
    guard entry?.selection != .book(bookID) else { return }
    withAnimation(AnimationSettings.shared.selectionSpring) {
      entry = NavigationEntry(selection: .book(bookID))
    }
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

/// Section header rendered above each group when the Home grid uses a grouped sort mode.
struct HomeBookGroupHeaderView: View {
  let group: HomeBookGroup

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(group.title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
      Text("·")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      Text(group.countText)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .monospacedDigit()
      Spacer(minLength: 0)
    }
    .padding(.top, 8)
    .padding(.bottom, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(group.headerText)
    .accessibilityIdentifier(AccessibilityID.Home.sectionHeader(group.id))
  }
}

/// Renders a single book thumbnail for the Home grid
struct HomeBookThumbnailView: View {
  @Environment(\.coverNamespace) private var coverNamespace
  let book: Book
  let gridItemSize: CGSize
  let onSelect: (NSManagedObjectID) -> Void

  var body: some View {
    Button {
      onSelect(book.objectID)
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
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.black.opacity(0.12))
          .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
      }
  }

  private var coverID: String {
    book.objectID.uriRepresentation().absoluteString
  }
}
