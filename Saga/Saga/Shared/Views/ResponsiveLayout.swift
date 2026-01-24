//
//  ResponsiveLayout.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

/// A two column responsive (configurable) layout, where each is scrollable separately.
struct ResponsiveLayout<ColumnA: View, ColumnB: View>: View {
    let columnA: ColumnA
    let columnB: ColumnB
    let threshold: CGFloat
    let widthRatio: CGFloat
    let outsidePadding: CGFloat
    let gap: CGFloat
    
    init(
        threshold: CGFloat = 576,
        /// The width of the first column, as a ratio. Second column will scale to fill
        widthRatio: CGFloat = 0.25,
        /// The padding around both columns
        outsidePadding: CGFloat = 0,
        /// The gap between columns
        gap: CGFloat = 0,
        @ViewBuilder columnA: () -> ColumnA,
        @ViewBuilder columnB: () -> ColumnB
    ) {
        self.threshold = threshold
        self.widthRatio = widthRatio
        self.outsidePadding = outsidePadding
        self.gap = gap
        self.columnA = columnA()
        self.columnB = columnB()
    }
    
    var body: some View {
        MeasuredContainer { size in
            if size.width >= threshold {
                twoColumnLayout(containerWidth: size.width)
            } else {
                oneColumnLayout
            }
        }
    }
    
    /// Each column scrolls separately, and the views are stickied to each other horizontally
    private func twoColumnLayout(containerWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ScrollView(.vertical) {
                columnA
                    .padding([.leading, .vertical], outsidePadding)
            }
            .frame(
                maxWidth: containerWidth * widthRatio,
                maxHeight: .infinity,
                alignment: .topTrailing
            )
            .scrollClipDisabled()

            scrollableContentView {
                columnB
                    .padding([.trailing, .vertical], outsidePadding)
            }
            .frame(alignment: .topLeading)
            .scrollClipDisabled()
        }
    }
    
    private var oneColumnLayout: some View {
        scrollableContentView {
            LazyVStack(alignment: .leading, spacing: gap) {
                columnA
                columnB
            }
            .padding(outsidePadding)
        }
    }

    private func scrollableContentView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content()
        }
    }

}
