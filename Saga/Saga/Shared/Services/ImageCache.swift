//
//  ImageCache.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Architecture Overview
//
// ImageCache provides a three-tier caching system for downsampled images:
//
// 1. MEMORY CACHE (NSCache)
//    - Fastest access, automatically evicted under memory pressure
//    - Two caches: one keyed by content hash, one by URL for quick lookups
//
// 2. DISK CACHE (PNG files)
//    - Persists across app launches in ~/Library/Caches/{diskCacheDirectoryName}/
//    - Files named by SHA256 hash of the cache key
//    - LRU eviction when disk limit exceeded (oldest files deleted first)
//
// 3. NETWORK (via URLSession)
//    - Downloads original image, downsamples to target size, then caches result
//    - Concurrency controlled by DownloadGate (max parallel downloads)
//    - Deduplication via InflightTasks (multiple requests share one download)
//
// Request lifecycle:
//   fetchImage() → check memory → check disk → acquire download permit →
//   download → downsample → store in memory + disk → return
//
// Cancellation support:
//   Views register interest via registerRequest(). When all views unregister,
//   the in-flight download is cancelled to avoid wasted work.

// MARK: - ImageCache

enum ImageCache {

  // MARK: Configuration

  /// UserDefaults key for the disk cache size limit (in GB)
  static let cacheLimitKey = "imageCacheLimitGB"

  /// Directory name for disk-cached images (inside ~/Library/Caches/)
  private static let diskCacheDirectoryName = "ImageCache"

  /// Maximum concurrent image downloads, based on CPU cores (6-12 range)
  static let maxConcurrentDownloads: Int = {
    let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let computed = cores * 2
    return min(12, max(6, computed))
  }()

  // MARK: Private State

  /// In-memory cache keyed by content hash (e.g., "isbn:123:200")
  private static let imageCache = NSCache<NSString, CGImage>()

  /// In-memory cache keyed by URL for fast lookups when URL is known
  private static let urlImageCache = NSCache<NSString, CGImage>()

  /// Tracks in-flight download tasks to deduplicate concurrent requests
  private static let inflightTasks = InflightTasks()

  /// Tracks which views are waiting for each image (for cancellation)
  private static let activeRequests = ActiveRequests()

  /// Semaphore-like gate limiting concurrent downloads
  private static let downloadGate = DownloadGate(maxConcurrent: maxConcurrentDownloads)

  /// Directory for disk-cached PNG files (falls back to temp directory if Caches unavailable)
  private static let diskCacheDirectory = CacheConfig.cacheDirectory(
    named: diskCacheDirectoryName,
    fallbackToTemp: true
  )!

  // MARK: - Public API

  /// Fetches an image, checking caches first, then downloading if needed.
  /// Returns a downsampled CGImage or nil if the fetch fails.
  static func fetchImage(
    url: URL,
    urlSession: URLSession,
    cacheKey: NSString,
    maxPixelSize: CGFloat
  ) async throws -> CGImage? {
    // Check memory and disk caches first
    if let cached = await cachedImage(for: cacheKey) {
      urlImageCache.setObject(cached, forKey: url.absoluteString as NSString)
      return cached
    }

    // Get or create a download task (deduplicates concurrent requests)
    let task = await inflightTasks.task(for: cacheKey) {
      Task(priority: .utility) {
        // Wait for a download slot
        guard let permit = await downloadGate.acquirePermit() else {
          throw CancellationError()
        }
        defer { permit.release() }

        guard !Task.isCancelled else { return nil }

        // Download the image
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let (data, _) = try await urlSession.data(for: request)

        guard !Task.isCancelled else { return nil }

        // Downsample and cache the result
        guard let image = downsampleImage(from: data, maxPixelSize: maxPixelSize) else {
          return nil
        }
        storeImage(image, for: cacheKey, urlKey: url.absoluteString as NSString)
        return image
      }
    }

    // Wait for the task and clean up
    do {
      let image = try await task.value
      await inflightTasks.removeTask(for: cacheKey)
      return image
    } catch is CancellationError {
      await inflightTasks.removeTask(for: cacheKey)
      throw CancellationError()
    } catch {
      await inflightTasks.removeTask(for: cacheKey)
      return nil
    }
  }

  /// Returns a cached image from memory only (no disk/network).
  /// Use for synchronous placeholder lookups.
  static func memoryCachedImage(for key: NSString) -> CGImage? {
    imageCache.object(forKey: key)
  }

  /// Returns a cached image by URL from memory only.
  static func urlCachedImage(for url: URL) -> CGImage? {
    urlImageCache.object(forKey: url.absoluteString as NSString)
  }

  /// Pauses or resumes all image downloads.
  /// Called during rapid scrolling to prioritize visible content.
  static func setDownloadsPaused(_ paused: Bool) {
    Task {
      await downloadGate.setPaused(paused)
    }
  }

  /// Registers a view's interest in an image. Call when a view appears.
  static func registerRequest(for key: NSString, id: UUID) async {
    await activeRequests.register(key: key, id: id)
  }

  /// Unregisters a view's interest. When no views remain interested,
  /// any in-flight download for this key is cancelled.
  static func unregisterRequest(for key: NSString, id: UUID) async {
    let isEmpty = await activeRequests.unregister(key: key, id: id)
    if isEmpty {
      await inflightTasks.cancelTask(for: key)
    }
  }

  // MARK: - Cache Management

  /// Returns the current disk cache size in bytes.
  static func diskCacheSizeBytes() -> Int64 {
    let fileManager = FileManager.default
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: diskCacheDirectory,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return 0
    }
    return urls.reduce(0) { total, url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return total + Int64(size)
    }
  }

  /// Clears all cached images (memory and disk).
  static func clearCache() async {
    await Task.detached(priority: .utility) {
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
    }.value
    imageCache.removeAllObjects()
    urlImageCache.removeAllObjects()
  }

  /// Enforces the disk cache size limit by deleting oldest files first (LRU).
  /// Called automatically after each new image is saved.
  static func enforceDiskCacheLimit() {
    let fileManager = FileManager.default
    let limit = diskCacheLimitBytes()

    // Unlimited cache, skip enforcement
    guard limit != .max else { return }

    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: diskCacheDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }

    // Collect file metadata
    var entries: [(url: URL, date: Date, size: Int64)] = []
    var total: Int64 = 0
    for url in urls {
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      let size = Int64(values?.fileSize ?? 0)
      let date = values?.contentModificationDate ?? .distantPast
      total += size
      entries.append((url, date, size))
    }

    // Under limit, nothing to do
    guard total > limit else { return }

    // Delete oldest files until under limit
    let sorted = entries.sorted { $0.date < $1.date }
    var remaining = total
    for entry in sorted {
      guard remaining > limit else { break }
      try? fileManager.removeItem(at: entry.url)
      remaining -= entry.size
    }
  }

  // MARK: - Memory Cache (Private)

  /// Checks memory cache, then disk cache, promoting disk hits to memory.
  private static func cachedImage(for key: NSString) async -> CGImage? {
    if let cached = imageCache.object(forKey: key) {
      return cached
    }
    let diskImage = await Task.detached(priority: .utility) {
      loadDiskCachedImage(for: key)
    }.value
    if let diskImage {
      imageCache.setObject(diskImage, forKey: key)
    }
    return diskImage
  }

  /// Stores an image in both memory caches and queues disk save.
  private static func storeImage(_ image: CGImage, for key: NSString, urlKey: NSString) {
    imageCache.setObject(image, forKey: key)
    urlImageCache.setObject(image, forKey: urlKey)
    Task.detached(priority: .utility) {
      saveDiskCachedImage(image, for: key)
    }
  }

  // MARK: - Disk Cache (Private)

  /// Returns the configured disk cache limit in bytes.
  private static func diskCacheLimitBytes() -> Int64 {
    CacheConfig.limitBytes(forKey: cacheLimitKey)
  }

  /// Generates a disk cache file URL from a cache key using SHA256 hash.
  private static func cacheFileURL(for key: NSString) -> URL {
    let data = Data(String(key).utf8)
    let digest = SHA256.hash(data: data)
    let filename = digest.map { String(format: "%02x", $0) }.joined()
    return diskCacheDirectory.appendingPathComponent(filename).appendingPathExtension("png")
  }

  /// Loads an image from disk cache, if it exists.
  private static func loadDiskCachedImage(for key: NSString) -> CGImage? {
    let url = cacheFileURL(for: key)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// Saves an image to disk cache as PNG, then enforces size limit.
  private static func saveDiskCachedImage(_ image: CGImage, for key: NSString) {
    let url = cacheFileURL(for: key)
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    enforceDiskCacheLimit()
  }

  // MARK: - Image Processing (Private)

  /// Downsamples image data to fit within maxPixelSize while preserving aspect ratio.
  /// Uses ImageIO for memory-efficient loading (doesn't decode full image).
  private static func downsampleImage(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
    let options =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
        kCGImageSourceCreateThumbnailWithTransform: true,
      ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  }
}

// MARK: - Concurrency Support Types

/// Tracks in-flight download tasks to deduplicate concurrent requests for the same image.
/// When multiple views request the same image, they share one download task.
private actor InflightTasks {
  private var tasks: [NSString: Task<CGImage?, Error>] = [:]

  /// Returns existing task for key, or creates one using the provided closure.
  func task(for key: NSString, create: @escaping () -> Task<CGImage?, Error>) -> Task<
    CGImage?, Error
  > {
    if let existing = tasks[key] {
      return existing
    }
    let task = create()
    tasks[key] = task
    return task
  }

  /// Removes a completed task from tracking.
  func removeTask(for key: NSString) {
    tasks[key] = nil
  }

  /// Cancels and removes a task (called when no views need the image anymore).
  func cancelTask(for key: NSString) {
    if let task = tasks[key] {
      task.cancel()
    }
    tasks[key] = nil
  }
}

/// Token returned by DownloadGate that must be released when download completes.
private struct DownloadPermit {
  let release: @Sendable () -> Void
}

/// Semaphore-like actor that limits concurrent downloads.
/// Supports pausing (during fast scrolling) and cancellation.
private actor DownloadGate {
  private let maxConcurrent: Int
  private var current = 0
  private var paused = false
  private var waiters: [Waiter] = []

  init(maxConcurrent: Int) {
    self.maxConcurrent = maxConcurrent
  }

  /// Pauses or resumes the gate. When paused, no new permits are granted.
  func setPaused(_ paused: Bool) {
    self.paused = paused
    if !paused {
      resumeWaiters()
    }
  }

  /// Acquires a download permit, waiting if at capacity or paused.
  /// Returns nil if the task was cancelled while waiting.
  func acquirePermit() async -> DownloadPermit? {
    if Task.isCancelled {
      return nil
    }
    if !paused, current < maxConcurrent {
      current += 1
      return DownloadPermit {
        Task { await self.release() }
      }
    }
    let id = UUID()
    let acquired = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiters.append(Waiter(id: id, continuation: continuation))
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
    guard acquired else { return nil }
    return DownloadPermit {
      Task { await self.release() }
    }
  }

  /// Releases a permit, allowing a waiting download to proceed.
  private func release() {
    current = max(0, current - 1)
    resumeWaiters()
  }

  /// Resumes waiting downloads up to the concurrency limit.
  private func resumeWaiters() {
    guard !paused else { return }
    while current < maxConcurrent, !waiters.isEmpty {
      let waiter = waiters.removeFirst()
      current += 1
      waiter.continuation.resume(returning: true)
    }
  }

  /// Cancels a waiting download (returns false to indicate cancellation).
  private func cancelWaiter(_ id: UUID) {
    if let index = waiters.firstIndex(where: { $0.id == id }) {
      let waiter = waiters.remove(at: index)
      waiter.continuation.resume(returning: false)
    }
  }

  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
  }
}

/// Tracks which views are interested in each image, enabling cancellation
/// when all interested views disappear.
private actor ActiveRequests {
  private var active: [NSString: Set<UUID>] = [:]

  /// Registers a view's interest in an image.
  func register(key: NSString, id: UUID) {
    var set = active[key] ?? Set()
    set.insert(id)
    active[key] = set
  }

  /// Unregisters a view. Returns true if no views remain interested.
  func unregister(key: NSString, id: UUID) -> Bool {
    guard var set = active[key] else { return true }
    set.remove(id)
    if set.isEmpty {
      active[key] = nil
      return true
    }
    active[key] = set
    return false
  }
}
