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
  static let maxEditorWidth: CGFloat = 640
}

/// Renders the full version of a book: a clean read mode, swapped for the editor on Edit.
struct BookContentView: View {
  @ObservedObject var book: Book
  let detailLayoutWidth: CGFloat
  /// Called after the book is deleted from the editor so the caller can navigate away.
  var onDelete: () -> Void = {}
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.scrollContextID) private var scrollContextID
  @Environment(\.coverNamespace) private var coverNamespace
  @EnvironmentObject private var bookNavigationViewModel: BookNavigationViewModel
  @State private var containerWidth: CGFloat = 0
  @State private var isEditing = false

  var body: some View {
    Group {
      if isEditing {
        editor
      } else {
        readView
      }
    }
    .botanicalPageBackground()
    .onChange(of: book.objectID) { _, _ in
      isEditing = false
    }
  }

  // MARK: - Modes

  private var editor: some View {
    BookEditorView(book: book, context: viewContext) { outcome in
      switch outcome {
      case .cancelled, .saved:
        isEditing = false
      case .deleted:
        isEditing = false
        onDelete()
      }
    }
    .id(book.objectID)
    .frame(maxWidth: Constants.maxEditorWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var readView: some View {
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
    .navigationTitle(book.title ?? "Untitled book")
    #if os(macOS)
      .navigationSubtitle(book.author ?? "")
      .toolbar(removing: .title)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isEditing = true
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        .keyboardShortcut("e", modifiers: .command)
        .help("Edit this book")
      }
    }
  }

  // MARK: - Cover column

  /// The "sidebar" of the two column view - shows less info and stays sticky in view
  private var sidebar: some View {
    coverImageView
      .frame(
        minWidth: Constants.minCoverWidth,
        maxWidth: Constants.maxCoverWidth,
        alignment: .center
      )
      .rotationEffect(bookNavigationViewModel.coverRotation, anchor: .center)
  }

  private var coverImageView: some View {
    let coverImageURLText = book.displayCoverURL?.absoluteString ?? "No image URL"
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
  }

  @ViewBuilder
  private var coverImageBase: some View {
    let coverImage = BookCoverImageView(book: book, targetSize: detailCoverSize)
      .frame(width: detailCoverSize.width, height: detailCoverSize.height)
      .physicalCoverShadow()
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

  // MARK: - Content column

  /// The right hand content view that grows to a max width of the two column view.
  private var content: some View {
    BookReadDetailsView(book: book)
      .frame(
        maxWidth: Constants.maxContentWidth,
        alignment: .topLeading
      )
  }
}
