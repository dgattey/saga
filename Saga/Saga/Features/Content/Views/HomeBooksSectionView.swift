//
//  HomeBooksSectionView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI
import CoreData

private struct Constants {
    static let outsidePadding: CGFloat = 32
    static let gridSpacing: CGFloat = 16
    static let minItemWidth: CGFloat = 140
    static let maxItemWidth: CGFloat = 220
}

/// Renders the books section in the Home view
struct HomeBooksSectionView: View {
    @EnvironmentObject private var viewModel: BooksViewModel
    @Binding var selection: SidebarSelection?
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
                        selection: $selection,
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
        let rawCount = (availableWidth + Constants.gridSpacing) / (Constants.minItemWidth + Constants.gridSpacing)
        let columnCount = max(1, Int(floor(rawCount)))
        let totalSpacing = CGFloat(columnCount - 1) * Constants.gridSpacing
        let width = (availableWidth - totalSpacing) / CGFloat(columnCount)
        return min(Constants.maxItemWidth, max(Constants.minItemWidth, width))
    }
}

/// Renders a single book thumbnail for the Home grid
struct HomeBookThumbnailView: View {
    @Environment(\.coverNamespace) private var coverNamespace
    @Environment(\.coverMatchActive) private var coverMatchActive
    let book: Book
    @Binding var selection: SidebarSelection?
    let gridItemSize: CGSize
    
    var body: some View {
        Button {
            withAnimation(AppAnimation.selectionSpring) {
                selection = .book(book.objectID)
            }
        } label: {
            coverImageView
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var coverImageView: some View {
        coverImageBase
            .opacity(showMatchedOverlay ? 0 : 1)
            .animation(AppAnimation.coverFade, value: showMatchedOverlay)
            .overlay {
                matchedCoverImage
                    .opacity(showMatchedOverlay ? 1 : 0)
                    .animation(AppAnimation.coverFade, value: showMatchedOverlay)
                    .allowsHitTesting(false)
            }
    }

    private var coverImageBase: some View {
        BookCoverImageView(book: book)
            .defaultShadow()
    }

    @ViewBuilder
    private var matchedCoverImage: some View {
        if let coverNamespace {
            let coverImage = BookCoverImageView(book: book)
                .defaultShadow()
                .rotationEffect(coverRotation)
                .animation(AppAnimation.coverRotation, value: selection)
            coverImage
                .frame(width: gridItemSize.width, height: gridItemSize.height)
                .matchedGeometryEffect(id: coverID, in: coverNamespace)
        }
    }

    private var showMatchedOverlay: Bool {
        shouldMatchGeometry && coverMatchActive && coverNamespace != nil
    }

    private var shouldMatchGeometry: Bool {
        selection?.matchedBookID == book.objectID
    }

    private var coverRotation: Angle {
        guard case .book(let selectedBookID) = selection,
              selectedBookID == book.objectID else {
            return .degrees(0)
        }
        return Angle.degrees(
            AppAnimation.coverRotationDegrees(from: book.hashValue, minDegrees: -1, maxDegrees: -8)
        )
    }

    private var coverID: String {
        book.objectID.uriRepresentation().absoluteString
    }
}
