//
//  NetworkCache.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Foundation

/// Manages the network cache for HTTP responses (used by URLSession)
enum NetworkCache {
  static let cacheLimitKey = "networkCacheLimitGB"

  /// Directory name for network cache (inside ~/Library/Caches/)
  private static let diskCacheDirectoryName = "NetworkResponses"

  /// Directory for disk-cached network responses
  private static let diskCacheDirectory = CacheConfig.cacheDirectory(named: diskCacheDirectoryName)

  /// Shared network cache for HTTP responses
  private static var cache: URLCache = {
    let diskCapacity = CacheConfig.capacity(fromLimitBytes: cacheLimitBytes())
    let memoryCapacity = CacheConfig.bytes(fromGB: CacheConfig.defaultLimitGB)
    return URLCache(
      memoryCapacity: memoryCapacity,
      diskCapacity: diskCapacity,
      directory: diskCacheDirectory
    )
  }()

  /// Shared URLSession configured with the network cache
  static let urlSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = cache
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.httpMaximumConnectionsPerHost = ImageCache.maxConcurrentDownloads
    return URLSession(configuration: configuration)
  }()

  /// Returns the configured network cache limit in bytes
  static func cacheLimitBytes() -> Int64 {
    CacheConfig.limitBytes(forKey: cacheLimitKey)
  }

  /// Returns the current disk usage of the network cache in bytes
  static func diskCacheSizeBytes() -> Int64 {
    Int64(cache.currentDiskUsage)
  }

  /// Clears the network cache
  static func clearCache() async {
    await Task.detached(priority: .utility) {
      cache.removeAllCachedResponses()
    }.value
  }

  /// Updates the network cache disk capacity based on current settings
  static func enforceCacheLimit() {
    cache.diskCapacity = CacheConfig.capacity(fromLimitBytes: cacheLimitBytes())
  }
}
