//
//  CachesViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Foundation
import Observation

/// Manages cache size tracking and clearing for both image and network caches
@MainActor
@Observable
final class CachesViewModel {
  var imageCacheSizeBytes: Int64 = 0
  var networkCacheSizeBytes: Int64 = 0
  @ObservationIgnored private var monitorTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var isClearing = false

  init() {}

  /// Starts refreshing cache sizes immediately and periodically while Settings is visible
  func startMonitoring() {
    refreshSizes()
    guard monitorTask == nil else { return }
    monitorTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, let self else { break }
        self.refreshSizes()
      }
    }
  }

  /// Stops periodic cache size refreshes when Settings is closed
  func stopMonitoring() {
    monitorTask?.cancel()
    monitorTask = nil
    refreshTask?.cancel()
    refreshTask = nil
  }

  /// Refreshes the current cache size values off the main thread (skipped during clearing)
  func refreshSizes() {
    guard !isClearing else { return }
    refreshTask?.cancel()
    refreshTask = Task { @MainActor [weak self] in
      let (imageBytes, networkBytes) = await Task.detached(priority: .utility) {
        (ImageCache.diskCacheSizeBytes(), NetworkCache.diskCacheSizeBytes())
      }.value
      guard !Task.isCancelled, let self, !self.isClearing else { return }
      self.imageCacheSizeBytes = imageBytes
      self.networkCacheSizeBytes = networkBytes
    }
  }

  /// Clears all caches (image and network)
  func clearAll() async {
    // Immediate feedback - show 0 right away and prevent timer from overwriting
    await MainActor.run {
      isClearing = true
      refreshTask?.cancel()
      imageCacheSizeBytes = 0
      networkCacheSizeBytes = 0
    }

    // Actually clear the caches
    await ImageCache.clearCache()
    await NetworkCache.clearCache()

    // Re-enable timer refreshes and confirm sizes
    await MainActor.run {
      isClearing = false
      refreshSizes()
    }
  }
}
