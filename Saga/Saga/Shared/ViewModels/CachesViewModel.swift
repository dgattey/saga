//
//  CachesViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import Combine
import Foundation

/// Manages cache size tracking and clearing for both image and network caches
final class CachesViewModel: ObservableObject {
  @Published var imageCacheSizeBytes: Int64 = 0
  @Published var networkCacheSizeBytes: Int64 = 0
  private var refreshTimer: AnyCancellable?
  private var refreshTask: Task<Void, Never>?
  private var isClearing = false

  init() {}

  /// Starts refreshing cache sizes immediately and periodically while Settings is visible
  func startMonitoring() {
    refreshSizes()
    guard refreshTimer == nil else { return }
    refreshTimer = Timer.publish(every: 5, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.refreshSizes()
      }
  }

  /// Stops periodic cache size refreshes when Settings is closed
  func stopMonitoring() {
    refreshTimer?.cancel()
    refreshTimer = nil
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
