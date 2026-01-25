//
//  AssetImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Shows an asset image with caching for the image data
struct AssetImageView: View {
  /// Shared image cache, larger than default
  private static let assetCache: URLCache = URLCache(
    memoryCapacity: 100 * 1024 * 1024 * 2,  // 2 GB in memory
    diskCapacity: 1024 * 1024 * 1024 * 5  // 5 GB on disk
  )

  private static let urlSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = assetCache
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.httpMaximumConnectionsPerHost = DownsampledImageCache.maxConcurrentDownloads
    return URLSession(configuration: configuration)
  }()

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
        urlSession: Self.urlSession,
        placeholder: AnyView(placeholderView),
        targetSize: targetSize
      )
    } else {
      placeholderView
    }
  }

  private var placeholderView: some View {
    Image(systemName: "photo")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .foregroundColor(.gray)
  }

}
