//
//  DownsampledAsyncImage.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Async image loader that downsamples to the rendered size.
struct DownsampledAsyncImage: View {
    private static let imageCache = NSCache<NSString, CGImage>()
    private static let cacheLimitKey = "downsampledImageCacheLimitGB"
    private static let defaultCacheLimitGB: Double = 10
    private static let diskCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let directory = base?.appendingPathComponent("DownsampledImages", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }()

    let url: URL
    let urlSession: URLSession
    let placeholder: AnyView

    @State private var targetSize: CGSize = .zero
    @State private var renderedImage: Image?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        contentView
            .task(id: loadKey) {
                await loadImage()
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateTargetSize(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newValue in
                            updateTargetSize(newValue)
                        }
                }
            )
    }

    @ViewBuilder
    private var contentView: some View {
        if let renderedImage {
            renderedImage
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if isLoading {
            ZStack {
                Rectangle().fill(.gray.opacity(0.5))
                ProgressView()
            }
        } else if didFail {
            placeholder
        } else {
            placeholder
        }
    }

    private func updateTargetSize(_ newValue: CGSize) {
        guard newValue != .zero else { return }
        if targetSize != newValue {
            targetSize = newValue
        }
    }

    private var loadKey: String {
        let maxPixelSize = bucketedMaxPixelSize(for: targetSize)
        return "\(url.absoluteString)|\(Int(maxPixelSize))"
    }

    private func loadImage() async {
        let maxPixelSize = bucketedMaxPixelSize(for: targetSize)
        guard maxPixelSize > 0 else { return }
        let cacheKey = loadKey as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            renderedImage = Image(decorative: cached, scale: displayScale)
            return
        }
        if let cached = loadDiskCachedImage(for: cacheKey) {
            Self.imageCache.setObject(cached, forKey: cacheKey)
            renderedImage = Image(decorative: cached, scale: displayScale)
            return
        }
        isLoading = true
        didFail = false
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, _) = try await urlSession.data(for: request)
            if let cgImage = downsampleImage(from: data, maxPixelSize: maxPixelSize) {
                Self.imageCache.setObject(cgImage, forKey: cacheKey)
                saveDiskCachedImage(cgImage, for: cacheKey)
                renderedImage = Image(decorative: cgImage, scale: displayScale)
            } else {
                didFail = true
            }
        } catch {
            didFail = true
        }
        isLoading = false
    }

    private var displayScale: CGFloat {
        #if os(macOS)
        return NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        return UIScreen.main.scale
        #endif
    }

    private func bucketedMaxPixelSize(for size: CGSize) -> CGFloat {
        guard size != .zero else { return 0 }
        let raw = max(size.width, size.height) * displayScale
        let bucket: CGFloat = 128
        return ceil(raw / bucket) * bucket
    }

    private func downsampleImage(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func diskCacheURL(for key: NSString) -> URL {
        let filename = key.replacingOccurrences(of: "/", with: "_")
        return Self.diskCacheDirectory.appendingPathComponent(filename).appendingPathExtension("png")
    }

    private func loadDiskCachedImage(for key: NSString) -> CGImage? {
        let url = diskCacheURL(for: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func saveDiskCachedImage(_ image: CGImage, for key: NSString) {
        let url = diskCacheURL(for: key)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        Self.enforceDiskCacheLimit()
    }

    static func diskCacheLimitBytes() -> Int64 {
        let stored = UserDefaults.standard.double(forKey: cacheLimitKey)
        let limitGB = stored > 0 ? stored : defaultCacheLimitGB
        if limitGB == 0 {
            return .max
        }
        return Int64(limitGB * 1024 * 1024 * 1024)
    }

    static func diskCacheSizeBytes() -> Int64 {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return urls.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    static func clearDiskCache() {
        let fileManager = FileManager.default
        if let urls = try? fileManager.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
        }
        imageCache.removeAllObjects()
    }

    static func clearAllCaches() {
        clearDiskCache()
        imageCache.removeAllObjects()
    }

    static func enforceDiskCacheLimit() {
        let fileManager = FileManager.default
        let limit = diskCacheLimitBytes()
        guard limit != .max else { return }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? .distantPast
            total += size
            entries.append((url, date, size))
        }
        guard total > limit else { return }
        let sorted = entries.sorted { $0.date < $1.date }
        var remaining = total
        for entry in sorted {
            guard remaining > limit else { break }
            try? fileManager.removeItem(at: entry.url)
            remaining -= entry.size
        }
    }
}
