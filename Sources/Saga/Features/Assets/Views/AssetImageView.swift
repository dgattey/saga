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
      .fill(Color.botanicalLeaf.opacity(0.10))
      .overlay {
        Image(systemName: "book.closed.fill")
          .font(.title2)
          .foregroundStyle(Color.botanicalSage.opacity(0.75))
      }
  }
}
