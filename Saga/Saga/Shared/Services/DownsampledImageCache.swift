//
//  DownsampledImageCache.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DownsampledImageCache {
  static let cacheLimitKey = "downsampledImageCacheLimitGB"
  private static let defaultCacheLimitGB: Double = 10
  private static let imageCache = NSCache<NSString, CGImage>()
  private static let urlImageCache = NSCache<NSString, CGImage>()
  private static let inflightTasks = InflightTasks()
  private static let activeRequests = ActiveRequests()
  static let maxConcurrentDownloads: Int = {
    let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let computed = cores * 2
    return min(12, max(6, computed))
  }()
  private static let downloadGate = DownloadGate(maxConcurrent: maxConcurrentDownloads)
  private static let diskCacheDirectory: URL = {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let directory = base?.appendingPathComponent("DownsampledImages", isDirectory: true)
    if let directory {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory ?? URL(fileURLWithPath: NSTemporaryDirectory())
  }()

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

  static func memoryCachedImage(for key: NSString) -> CGImage? {
    imageCache.object(forKey: key)
  }

  static func urlCachedImage(for url: URL) -> CGImage? {
    urlImageCache.object(forKey: url.absoluteString as NSString)
  }

  static func fetchImage(
    url: URL,
    urlSession: URLSession,
    cacheKey: NSString,
    maxPixelSize: CGFloat
  ) async throws -> CGImage? {
    if let cached = await cachedImage(for: cacheKey) {
      urlImageCache.setObject(cached, forKey: url.absoluteString as NSString)
      return cached
    }
    let task = await inflightTasks.task(for: cacheKey) {
      Task(priority: .utility) {
        guard let permit = await downloadGate.acquirePermit() else {
          throw CancellationError()
        }
        defer { permit.release() }
        guard !Task.isCancelled else { return nil }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let (data, _) = try await urlSession.data(for: request)
        guard !Task.isCancelled else { return nil }
        guard let image = downsampleImage(from: data, maxPixelSize: maxPixelSize) else {
          return nil
        }
        storeImage(image, for: cacheKey, urlKey: url.absoluteString as NSString)
        return image
      }
    }
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

  static func setDownloadsPaused(_ paused: Bool) {
    Task {
      await downloadGate.setPaused(paused)
    }
  }

  static func registerRequest(for key: NSString, id: UUID) async {
    await activeRequests.register(key: key, id: id)
  }

  static func unregisterRequest(for key: NSString, id: UUID) async {
    let isEmpty = await activeRequests.unregister(key: key, id: id)
    if isEmpty {
      await inflightTasks.cancelTask(for: key)
    }
  }

  private static func storeImage(_ image: CGImage, for key: NSString, urlKey: NSString) {
    imageCache.setObject(image, forKey: key)
    urlImageCache.setObject(image, forKey: urlKey)
    Task.detached(priority: .utility) {
      saveDiskCachedImage(image, for: key)
    }
  }

  private static func diskCacheLimitBytes() -> Int64 {
    let stored = UserDefaults.standard.double(forKey: cacheLimitKey)
    let limitGB = stored > 0 ? stored : defaultCacheLimitGB
    if limitGB == 0 {
      return .max
    }
    return Int64(limitGB * 1024 * 1024 * 1024)
  }

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

  static func clearCache() {
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
    urlImageCache.removeAllObjects()
  }

  static func enforceDiskCacheLimit() {
    let fileManager = FileManager.default
    let limit = diskCacheLimitBytes()
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

  private static func cacheFileURL(for key: NSString) -> URL {
    let data = Data(String(key).utf8)
    let digest = SHA256.hash(data: data)
    let filename = digest.map { String(format: "%02x", $0) }.joined()
    return diskCacheDirectory.appendingPathComponent(filename).appendingPathExtension("png")
  }

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
}

private actor InflightTasks {
  private var tasks: [NSString: Task<CGImage?, Error>] = [:]

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

  func removeTask(for key: NSString) {
    tasks[key] = nil
  }

  func cancelTask(for key: NSString) {
    if let task = tasks[key] {
      task.cancel()
    }
    tasks[key] = nil
  }
}

private struct DownloadPermit {
  let release: @Sendable () -> Void
}

private actor DownloadGate {
  private let maxConcurrent: Int
  private var current = 0
  private var paused = false
  private var waiters: [Waiter] = []

  init(maxConcurrent: Int) {
    self.maxConcurrent = maxConcurrent
  }

  func setPaused(_ paused: Bool) {
    self.paused = paused
    if !paused {
      resumeWaiters()
    }
  }

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

  private func release() {
    current = max(0, current - 1)
    resumeWaiters()
  }

  private func resumeWaiters() {
    guard !paused else { return }
    while current < maxConcurrent, !waiters.isEmpty {
      let waiter = waiters.removeFirst()
      current += 1
      waiter.continuation.resume(returning: true)
    }
  }

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

private actor ActiveRequests {
  private var active: [NSString: Set<UUID>] = [:]

  func register(key: NSString, id: UUID) {
    var set = active[key] ?? Set()
    set.insert(id)
    active[key] = set
  }

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
