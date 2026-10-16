//
//  AssetImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Shows an asset image with caching for the image data
struct AssetImageView: View {
  let asset: Asset?
  let targetSize: CGSize?

  init(asset: Asset?, targetSize: CGSize? = nil) {
    self.asset = asset
    self.targetSize = targetSize
  }

  var body: some View {
    if let asset = asset,
      let url = asset.assetURL
    {
      DownsampledAsyncImage(
        url: url,
        urlSession: NetworkCache.urlSession,
        placeholder: AnyView(placeholderView),
        targetSize: targetSize
      )
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
