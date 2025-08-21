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
    
    @State private var containerWidth: CGFloat = 0
    
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
        Group {
            if containerWidth >= threshold {
                twoColumnLayout
            } else {
                oneColumnLayout
            }
        }
        .overlay(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        containerWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
            }
        )
    }
    
    /// Each column scrolls separately, and the views are stickied to each other horizontally
    private var twoColumnLayout: some View {
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
            
            ScrollView(.vertical) {
                columnB
                    .padding([.trailing, .vertical], outsidePadding)
            }
            .frame(alignment: .topLeading)
            .scrollClipDisabled()
        }
        .containerRelativeFrame([.vertical]) { height, _ in
            height
        }
    }
    
    private var oneColumnLayout: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: gap) {
                columnA
                columnB
            }
            .padding(outsidePadding)
        }
    }
}
