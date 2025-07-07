//
//  AssetImageView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//


import SwiftUI
import CachedAsyncImage

struct AssetImageView: View {
    let asset: Asset?

    var body: some View {
        if let asset = asset,
           let url = asset.assetURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
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
