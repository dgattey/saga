//
//  CacheConfig.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Foundation

/// Shared configuration for cache limits, directories, and conversions
enum CacheConfig {
  static let bytesPerGB: Int64 = 1024 * 1024 * 1024
  static let defaultLimitGB: Double = 5

  // MARK: - Cache Limits

  /// Calculates cache limit in bytes (Int64) from UserDefaults
  static func limitBytes(forKey key: String, defaultGB: Double = defaultLimitGB) -> Int64 {
    let isExplicitlySet = UserDefaults.standard.object(forKey: key) != nil
    let stored = UserDefaults.standard.double(forKey: key)
    let limitGB = isExplicitlySet ? stored : defaultGB
    if limitGB == 0 {
      return .max
    }
    return Int64(limitGB * Double(bytesPerGB))
  }

  /// Converts limit bytes to Int capacity, handling .max case for URLCache
  static func capacity(fromLimitBytes limitBytes: Int64) -> Int {
    limitBytes == .max ? Int.max : Int(limitBytes)
  }

  /// Converts GB to bytes as Int (for memory capacity)
  static func bytes(fromGB gb: Double) -> Int {
    Int(gb * Double(bytesPerGB))
  }

  // MARK: - Cache Directories

  /// Creates and returns a cache directory in ~/Library/Caches/ with the given name.
  /// Creates the directory if it doesn't exist.
  /// - Parameters:
  ///   - name: The directory name (e.g., "ImageCache", "NetworkResponses")
  ///   - fallbackToTemp: If true, returns temp directory when Caches unavailable; if false, returns nil
  /// - Returns: The cache directory URL, or nil/temp based on fallbackToTemp
  static func cacheDirectory(named name: String, fallbackToTemp: Bool = false) -> URL? {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let directory = base?.appendingPathComponent(name, isDirectory: true)
    if let directory {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    if fallbackToTemp, directory == nil {
      return URL(fileURLWithPath: NSTemporaryDirectory())
    }
    return directory
  }
}
