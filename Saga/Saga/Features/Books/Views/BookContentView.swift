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
    static let minCoverWidth: CGFloat = 96
    static let maxCoverWidth: CGFloat = 192
    static let maxContentWidth: CGFloat = 544
}

/// Renders the full version of a book
struct BookContentView: View {
    
    var book: Book
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
            columnA: { sidebar },
            columnB: { content }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .textSelection(.enabled)
        .navigationTitle(title)
#if os(macOS)
        .navigationSubtitle(author)
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
    }
    
    var coverImageView: some View {
        let coverImageURLText = book.coverImage?.assetURL?.absoluteString ?? "No image URL"
        return BookCoverImageView(book: book)
            .defaultShadow()
            .randomRotation(from: book.hashValue, minDegrees: -1, maxDegrees: -8)
            .contextMenu {
                CopyButton(labelText: "Copy image URL", value: coverImageURLText)
                if let isbn = book.isbn?.stringValue {
                    CopyButton(
                        labelText: "Copy ISBN",
                        value: isbn
                    )
                }
            }
            .copyable([coverImageURLText])
#if os(macOS)
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
        VStack(alignment: .leading, spacing: 16) {
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
        Text(title).font(.largeTitle)
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
