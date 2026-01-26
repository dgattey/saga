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
  private var isClearing = false

  init() {
    refreshSizes()
    startRefreshTimer()
  }

  /// Refreshes the current cache size values (skipped during clearing)
  func refreshSizes() {
    guard !isClearing else { return }
    imageCacheSizeBytes = ImageCache.diskCacheSizeBytes()
    networkCacheSizeBytes = NetworkCache.diskCacheSizeBytes()
  }

  /// Clears all caches (image and network)
  func clearAll() async {
    // Immediate feedback - show 0 right away and prevent timer from overwriting
    await MainActor.run {
      isClearing = true
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

  /// Starts the periodic timer to refresh cache sizes
  private func startRefreshTimer() {
    refreshTimer = Timer.publish(every: 5, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.refreshSizes()
      }
  }
}
