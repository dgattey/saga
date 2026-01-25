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
  @ObservedObject var book: Book
  let detailLayoutWidth: CGFloat
  @Environment(\.scrollContextID) private var scrollContextID
  @Environment(\.coverNamespace) private var coverNamespace
  @EnvironmentObject private var bookNavigationViewModel: BookNavigationViewModel
  @StateObject private var viewModel: BookDetailViewModel
  @State private var containerWidth: CGFloat = 0

  @FocusState private var focusedField: BookDetailViewModel.Field?

  init(book: Book, detailLayoutWidth: CGFloat) {
    self.book = book
    self.detailLayoutWidth = detailLayoutWidth
    _viewModel = StateObject(wrappedValue: BookDetailViewModel(book: book))
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
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded { focusedField = nil }
    )
    .onChange(of: focusedField) { _, newValue in
      viewModel.handleFocusChange(to: newValue)
    }
    .onChange(of: book.objectID) { _, _ in
      viewModel.setBook(book)
    }
    .navigationTitle(viewModel.displayTitle)
    #if os(macOS)
      .navigationSubtitle(viewModel.displayAuthor)
      .toolbar(removing: .title)
    #endif
    .onExitCommand { focusedField = nil }
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
      titleField
      authorField
    }
  }

  /// The right hand content view that grows to a max width of the two column view. Has
  /// a lot of data and is scrollable.
  var content: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      metadataStack
      labeledField("Rating") {
        StarRatingView(
          rating: Binding(
            get: { viewModel.ratingDraft },
            set: { newValue in
              viewModel.updateRatingDraft(newValue)
              focusedField = .rating
            }
          )
        )
      }
      labeledField("ISBN") {
        TextField("ISBN-13", text: $viewModel.isbnDraft)
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .isbn)
          .onChange(of: viewModel.isbnDraft) { _, newValue in
            viewModel.updateISBNDraft(newValue)
          }
          .onSubmit { viewModel.commitField(.isbn) }
      }
      labeledField("Image URL") {
        TextField("Cover image URL", text: $viewModel.coverURLDraft)
          .textFieldStyle(.roundedBorder)
          .focused($focusedField, equals: .coverURL)
          .onSubmit { viewModel.commitField(.coverURL) }
      }
      BookReadingStatusView(book: book)
      labeledField("Description") {
        TextEditor(text: $viewModel.reviewDraft)
          .focused($focusedField, equals: .review)
          .onChange(of: viewModel.reviewDraft) { _, newValue in
            viewModel.updateReviewDraft(newValue)
          }
          .frame(minHeight: 120)
      }
    }
    .frame(
      maxWidth: Constants.maxContentWidth,
      alignment: .topLeading
    )
  }

  private var titleField: some View {
    TextField("Title", text: $viewModel.titleDraft)
      .font(.largeTitleBold)
      .textFieldStyle(.plain)
      .focused($focusedField, equals: .title)
      .onChange(of: viewModel.titleDraft) { _, newValue in
        viewModel.updateTitleDraft(newValue)
      }
      .onSubmit { viewModel.commitField(.title) }
  }

  private var authorField: some View {
    TextField("Author", text: $viewModel.authorDraft)
      .font(.title2)
      .textFieldStyle(.plain)
      .focused($focusedField, equals: .author)
      .onChange(of: viewModel.authorDraft) { _, newValue in
        viewModel.updateAuthorDraft(newValue)
      }
      .onSubmit { viewModel.commitField(.author) }
  }

  private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      content()
    }
  }

}
