//
//  ConflictInfo.swift
//  Saga
//
//  Value types describing two-way sync behavior and conflict state.
//

import Foundation

// MARK: - TwoWaySyncConfig

/// Configuration for two-way sync behavior
struct TwoWaySyncConfig {
  /// Minimum interval between sync operations (seconds)
  var syncDebounceInterval: TimeInterval = 2.0

  /// Whether to auto-publish entries after creating/updating
  var autoPublish: Bool = true

  /// Conflict resolution strategy
  var conflictResolution: ConflictResolution = .latestWins

  enum ConflictResolution {
    case latestWins  // Compare updatedAt timestamps, skip if server is newer
    case localWins  // Always push local changes (overwrites server)
  }
}

// MARK: - ConflictInfo

/// Information about a sync conflict where server data was newer
struct ConflictInfo: Identifiable {
  let id = UUID()
  let entityType: String
  let entityId: String
  let entityTitle: String?
  let serverDate: Date
  let localDate: Date
}
