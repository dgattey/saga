//
//  AssetImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//


import SwiftUI
import CachedAsyncImage

/// Shows an asset image with caching for the image data
struct AssetImageView: View {
    
    /// Shared image cache, larger than default
    private static let assetCache: URLCache = URLCache(
        memoryCapacity: 100 * 1024 * 1024 * 2,  // 2 GB in memory
        diskCapacity: 1024 * 1024 * 1024 * 5    // 5 GB on disk
    )
    
    let asset: Asset?

    var body: some View {
        if let asset = asset,
           let url = asset.assetURL {
            CachedAsyncImage(url: url, urlCache: Self.assetCache) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Rectangle().fill(.gray.opacity(0.5))
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.gray)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            Image(systemName: "photo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.gray)
        }
    }
}
