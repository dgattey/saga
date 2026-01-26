//
//  BookContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

private struct Constants {
  static let columnGap: CGFloat = 48
  static let outsidePadding: CGFloat = 32
  static let layoutThreshold: CGFloat = 576
  static let layoutWidthRatio: CGFloat = 0.25
  static let minCoverWidth: CGFloat = 96
  static let maxCoverWidth: CGFloat = 192
  static let maxContentWidth: CGFloat = 544
}

/// Renders the full version of a book
struct BookContentView: View {
  var book: Book
  let detailLayoutWidth: CGFloat
  @Environment(\.scrollContextID) private var scrollContextID
  @Environment(\.coverNamespace) private var coverNamespace
  @EnvironmentObject private var bookNavigationViewModel: BookNavigationViewModel
  @State private var containerWidth: CGFloat = 0
  var title: String {
    book.title ?? "Untitled book"
  }
  var author: String {
    book.author ?? "Unknown author"
  }

  var body: some View {
    ResponsiveLayout(
      outsidePadding: Constants.outsidePadding,
      gap: Constants.columnGap,
      scrollScope: ScrollScope.book(book.objectID),
      scrollContextID: scrollContextID,
      columnA: { sidebar },
      columnB: { content }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .readSize { size in
      if size.width != containerWidth {
        containerWidth = size.width
      }
    }
    .textSelection(.enabled)
    .navigationTitle(title)
    #if os(macOS)
      .navigationSubtitle(author)
      .toolbar(removing: .title)
    #endif
  }

  /// The "sidebar" of the two column view - shows less info and stays sticky in view
  var sidebar: some View {
    coverImageView
      .frame(
        minWidth: Constants.minCoverWidth,
        maxWidth: Constants.maxCoverWidth,
        alignment: .center
      )
      .rotationEffect(bookNavigationViewModel.coverRotation, anchor: .center)
  }

  var coverImageView: some View {
    let coverImageURLText = book.coverImage?.assetURL?.absoluteString ?? "No image URL"
    return
      coverImageBase
      .contextMenu {
        CopyButton(labelText: "Copy image URL", value: coverImageURLText)
        if let isbn = book.isbn?.stringValue {
          CopyButton(
            labelText: "Copy ISBN",
            value: isbn
          )
        }
      }
      #if os(macOS)
        .copyable([coverImageURLText])
        .help(coverImageURLText)
      #endif
      .background {
        Circle()
          .foregroundStyle(
            Color
              .accent
              .mix(with: .primary, by: 0.25)
          )
          .padding(-12)
          .defaultShadow()
      }
  }

  @ViewBuilder
  private var coverImageBase: some View {
    let coverImage = BookCoverImageView(book: book, targetSize: detailCoverSize)
      .frame(width: detailCoverSize.width, height: detailCoverSize.height)
      .defaultShadow()
    if let coverNamespace {
      coverImage
        .matchedGeometryEffect(id: coverID, in: coverNamespace)
    } else {
      coverImage
    }
  }

  private var detailCoverSize: CGSize {
    let width = detailCoverWidth
    return CGSize(
      width: width,
      height: width / BookCoverImageView.coverAspectRatio
    )
  }

  private var detailCoverWidth: CGFloat {
    let width = resolvedContainerWidth
    guard width > 0 else {
      return Constants.maxCoverWidth
    }
    return coverWidth(for: width)
  }

  private var resolvedContainerWidth: CGFloat {
    if containerWidth > 0 {
      return containerWidth
    }
    if detailLayoutWidth > 0 {
      return detailLayoutWidth
    }
    return 0
  }

  private func coverWidth(for width: CGFloat) -> CGFloat {
    if width >= Constants.layoutThreshold {
      let columnWidth = width * Constants.layoutWidthRatio
      let availableWidth = max(0, columnWidth - Constants.outsidePadding)
      return clampCoverWidth(availableWidth)
    }
    let availableWidth = max(0, width - (Constants.outsidePadding * 2))
    return clampCoverWidth(availableWidth)
  }

  private func clampCoverWidth(_ width: CGFloat) -> CGFloat {
    min(Constants.maxCoverWidth, max(Constants.minCoverWidth, width))
  }

  private var coverID: String {
    book.objectID.uriRepresentation().absoluteString
  }

  /// The top level metadata stack
  var metadataStack: some View {
    VStack(alignment: .leading, spacing: 8) {
      titleView
      authorView
    }
  }

  /// The right hand content view that grows to a max width of the two column view. Has
  /// a lot of data and is scrollable.
  var content: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      metadataStack
      StarRatingView(rating: book.rating?.intValue ?? 0)

      Text(book.isbn?.stringValue ?? "No ISBN")

      BookReadingStatusView(book: book)

      reviewView
    }
    .frame(
      maxWidth: Constants.maxContentWidth,
      alignment: .topLeading
    )
  }

  var titleView: some View {
    Text(title).font(.largeTitleBold)
  }

  var authorView: some View {
    Text(author).font(.title2)
  }

  var reviewView: some View {
    guard let attributedString = book.reviewDescription?.attributedString else {
      return AnyView(EmptyView())
    }
    return AnyView(
      AttributedTextViewer(attributedString: attributedString)
    )
  }
}
