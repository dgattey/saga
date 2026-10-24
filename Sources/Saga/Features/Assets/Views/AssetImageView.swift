//
//  AssetImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Shows an asset image with caching for the image data
struct AssetImageView: View {
  let url: URL?
  let targetSize: CGSize?

  init(asset: Asset?, targetSize: CGSize? = nil) {
    self.init(url: asset?.assetURL, targetSize: targetSize)
  }

  init(url: URL?, targetSize: CGSize? = nil) {
    self.url = url
    self.targetSize = targetSize
  }

  var body: some View {
    if let url {
      DownsampledAsyncImage(
        url: url,
        urlSession: NetworkCache.urlSession,
        placeholder: AnyView(placeholderView),
        targetSize: targetSize
      )
      .id(url)
    } else {
      placeholderView
    }
  }

  private var placeholderView: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color.botanicalCoverPlaceholderFill)
      .overlay {
        Image(systemName: "book.closed.fill")
          .font(placeholderIconFont)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(Color.botanicalCoverPlaceholderIcon)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.botanicalCoverPlaceholderBorder, lineWidth: 0.75)
      }
  }

  private var placeholderIconFont: Font {
    if let width = targetSize?.width, width <= 50 {
      return .system(size: max(14, round(width * 0.42)), weight: .medium)
    }
    return .title2.weight(.medium)
  }
}
