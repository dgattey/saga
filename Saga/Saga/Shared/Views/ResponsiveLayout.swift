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
  let scrollScope: ScrollScope?
  let scrollContextID: UUID?

  init(
    threshold: CGFloat = 576,
    /// The width of the first column, as a ratio. Second column will scale to fill
    widthRatio: CGFloat = 0.25,
    /// The padding around both columns
    outsidePadding: CGFloat = 0,
    /// The gap between columns
    gap: CGFloat = 0,
    /// Optional scroll persistence scope for contained scroll views
    scrollScope: ScrollScope? = nil,
    /// Optional scroll persistence context identifier
    scrollContextID: UUID? = nil,
    @ViewBuilder columnA: () -> ColumnA,
    @ViewBuilder columnB: () -> ColumnB
  ) {
    self.threshold = threshold
    self.widthRatio = widthRatio
    self.outsidePadding = outsidePadding
    self.gap = gap
    self.scrollScope = scrollScope
    self.scrollContextID = scrollContextID
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
      scrollableContentView(region: "sidebar") {
        columnA
          .padding([.leading, .vertical], outsidePadding)
      }
      .frame(
        maxWidth: containerWidth * widthRatio,
        maxHeight: .infinity,
        alignment: .topTrailing
      )
      .scrollClipDisabled()

      scrollableContentView(region: "content") {
        columnB
          .padding([.trailing, .vertical], outsidePadding)
      }
      .frame(alignment: .topLeading)
      .scrollClipDisabled()
    }
  }

  private var oneColumnLayout: some View {
    scrollableContentView(region: "single") {
      LazyVStack(alignment: .leading, spacing: gap) {
        columnA
        columnB
      }
      .padding(outsidePadding)
    }
  }

  @ViewBuilder
  private func scrollableContentView<Content: View>(
    region: String,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    if let scrollScope {
      PersistentScrollView(
        scrollKey: ScrollKey(
          scope: scrollScope,
          region: region,
          contextID: scrollContextID
        )
      ) {
        content()
      }
    } else {
      ScrollView(.vertical) {
        content()
      }
    }
  }

}
