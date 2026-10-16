//
//  DownsampledAsyncImage.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

/// Async image loader that downsamples to the rendered size.
struct DownsampledAsyncImage: View {
  @Environment(\.displayScale) private var displayScale

  let url: URL
  let urlSession: URLSession
  let placeholder: AnyView
  let targetSize: CGSize?

  init(
    url: URL,
    urlSession: URLSession,
    placeholder: AnyView,
    targetSize: CGSize? = nil
  ) {
    self.url = url
    self.urlSession = urlSession
    self.placeholder = placeholder
    self.targetSize = targetSize
  }

  @State private var targetMaxPixelSize: CGFloat = 0
  @State private var lastMeasuredSize: CGSize = .zero
  @State private var renderedImage: Image?
  @State private var didFail = false
  @State private var requestID = UUID()
  @State private var activeCacheKey: NSString?
  @State private var activeURLKey: String?
  @State private var sizeUpdateTask: Task<Void, Never>?

  var body: some View {
    contentView
      .task(id: loadKey) {
        let maxPixelSize = effectiveMaxPixelSize
        let cacheKey = loadKey as NSString
        let urlKey = url.absoluteString
        await loadImage(
          cacheKey: cacheKey,
          maxPixelSize: maxPixelSize,
          urlKey: urlKey
        )
      }
      .onDisappear {
        sizeUpdateTask?.cancel()
        sizeUpdateTask = nil
        if let activeCacheKey {
          let keyToUnregister = activeCacheKey
          self.activeCacheKey = nil
          Task {
            await ImageCache.unregisterRequest(for: keyToUnregister, id: requestID)
          }
        }
      }
      .background(sizeReaderView)
      .onChange(of: targetSize) { _, newValue in
        guard let newValue, newValue != .zero else { return }
        applyTargetSize(newValue)
      }
      .onChange(of: displayScale) { _, _ in
        if resolvedTargetSize == nil {
          scheduleTargetSizeUpdate(lastMeasuredSize)
        }
      }
  }

  @ViewBuilder
  private var contentView: some View {
    if let renderedImage {
      renderedImage
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else if let cachedImage {
      cachedImage
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else if didFail {
      placeholder
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.botanicalLeaf.opacity(0.08))
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private var sizeReaderView: some View {
    if resolvedTargetSize == nil {
      GeometryReader { proxy in
        Color.clear
          .onAppear {
            scheduleTargetSizeUpdate(proxy.size)
          }
          .onChange(of: proxy.size) { _, newValue in
            scheduleTargetSizeUpdate(newValue)
          }
      }
    }
  }

  private var resolvedTargetSize: CGSize? {
    guard let targetSize, targetSize != .zero else { return nil }
    return targetSize
  }

  private var cachedImage: Image? {
    let size = resolvedTargetSize ?? lastMeasuredSize
    guard size != .zero else { return nil }
    let maxPixelSize = bucketedMaxPixelSize(for: size)
    return cachedImage(for: maxPixelSize)
  }

  private func scheduleTargetSizeUpdate(_ newValue: CGSize) {
    guard newValue != .zero else { return }
    sizeUpdateTask?.cancel()
    let size = newValue
    sizeUpdateTask = Task { @MainActor in
      await Task.yield()
      guard !Task.isCancelled else { return }
      applyTargetSize(size)
    }
  }

  private func applyTargetSize(_ newValue: CGSize) {
    let maxPixelSize = bucketedMaxPixelSize(for: newValue)
    guard maxPixelSize > 0 else { return }
    lastMeasuredSize = newValue
    if renderedImage == nil,
      let cachedImage = cachedImage(for: maxPixelSize)
    {
      renderedImage = cachedImage
    }
    if renderedImage != nil, maxPixelSize <= targetMaxPixelSize {
      return
    }
    guard maxPixelSize != targetMaxPixelSize else { return }
    targetMaxPixelSize = maxPixelSize
  }

  private var effectiveMaxPixelSize: CGFloat {
    if let resolvedTargetSize {
      return bucketedMaxPixelSize(for: resolvedTargetSize)
    }
    if targetMaxPixelSize > 0 {
      return targetMaxPixelSize
    }
    return 0
  }

  private var loadKey: String {
    "\(url.absoluteString)|\(Int(effectiveMaxPixelSize))"
  }

  private func cacheKey(for maxPixelSize: CGFloat) -> NSString {
    "\(url.absoluteString)|\(Int(maxPixelSize))" as NSString
  }

  private func loadImage(cacheKey: NSString, maxPixelSize: CGFloat, urlKey: String) async {
    guard maxPixelSize > 0 else { return }
    guard !Task.isCancelled else { return }

    // Fast path: if already in memory cache, `cachedImage` renders synchronously in `contentView`
    // without needing any @State mutation unless stale state from a previous URL exists.
    if let memoryCached = ImageCache.memoryCachedImage(for: cacheKey) {
      if activeURLKey != nil && activeURLKey != urlKey {
        activeURLKey = urlKey
        renderedImage = Image(decorative: memoryCached, scale: displayScale)
      }
      if didFail {
        didFail = false
      }
      return
    }

    if activeURLKey != urlKey {
      activeURLKey = urlKey
      if renderedImage != nil {
        renderedImage = nil
      }
      if didFail {
        didFail = false
      }
    }
    if let previousKey = activeCacheKey,
      previousKey != cacheKey
    {
      await ImageCache.unregisterRequest(for: previousKey, id: requestID)
    }
    if activeCacheKey != cacheKey {
      activeCacheKey = cacheKey
      didFail = false
      await ImageCache.registerRequest(for: cacheKey, id: requestID)
    }
    do {
      let cgImage = try await ImageCache.fetchImage(
        url: url,
        urlSession: urlSession,
        cacheKey: cacheKey,
        maxPixelSize: maxPixelSize
      )
      guard activeCacheKey == cacheKey,
        activeURLKey == urlKey
      else {
        return
      }
      if let cgImage {
        try Task.checkCancellation()
        renderedImage = Image(decorative: cgImage, scale: displayScale)
        didFail = false
      } else {
        if !Task.isCancelled {
          didFail = true
        }
      }
    } catch is CancellationError {
      return
    } catch {
      if activeCacheKey == cacheKey, activeURLKey == urlKey {
        didFail = true
      }
    }
  }

  private func cachedImage(for maxPixelSize: CGFloat) -> Image? {
    guard maxPixelSize > 0 else { return nil }
    let key = cacheKey(for: maxPixelSize)
    if let cgImage = ImageCache.memoryCachedImage(for: key) {
      return Image(decorative: cgImage, scale: displayScale)
    }
    if let cgImage = ImageCache.urlCachedImage(for: url) {
      return Image(decorative: cgImage, scale: displayScale)
    }
    return nil
  }

  private func bucketedMaxPixelSize(for size: CGSize) -> CGFloat {
    guard size != .zero else { return 0 }
    let raw = max(size.width, size.height) * displayScale
    let bucket: CGFloat = 128
    return ceil(raw / bucket) * bucket
  }
}
