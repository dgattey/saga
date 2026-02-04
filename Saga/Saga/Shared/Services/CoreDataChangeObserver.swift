//
//  CoreDataChangeObserver.swift
//  Saga
//
//  Observes CoreData changes via NSManagedObjectContextDidSaveNotification
//  to automatically trigger sync operations for two-way Contentful sync.
//

import Combine
import CoreData
import Foundation

/// Represents a change detected in CoreData
struct LocalChange: Equatable, Hashable {
  enum ChangeType: String {
    case insert
    case update
    case delete
  }

  let objectID: NSManagedObjectID
  let entityName: String
  let contentfulId: String
  let changeType: ChangeType
  let timestamp: Date

  func hash(into hasher: inout Hasher) {
    hasher.combine(objectID)
    hasher.combine(changeType.rawValue)
  }

  static func == (lhs: LocalChange, rhs: LocalChange) -> Bool {
    lhs.objectID == rhs.objectID && lhs.changeType == rhs.changeType
  }
}

/// Protocol for objects that can be synced to Contentful
protocol ContentfulSyncable {
  /// The Contentful entry/asset ID
  var id: String { get }
  /// When the object was last updated locally
  var updatedAt: Date? { get }
  /// Whether this object has local changes not yet synced
  var isDirty: Bool { get set }
  /// The Contentful version number for optimistic locking
  var contentfulVersion: Int { get set }
}

/// Observes CoreData context saves and collects changes for sync
final class CoreDataChangeObserver: ObservableObject {
  /// Queue of pending changes to sync
  @Published private(set) var pendingChanges: [LocalChange] = []

  /// Entities that should be observed for sync
  private let syncableEntities: Set<String> = ["Book", "Asset"]

  /// Publishers for change notifications
  private var cancellables = Set<AnyCancellable>()

  /// The managed object context to observe
  private weak var context: NSManagedObjectContext?

  /// Whether observation is currently paused (e.g., during incoming sync)
  private var isPaused = false

  /// Debounce timer for batching changes
  private var debounceTimer: Timer?
  private let debounceInterval: TimeInterval = 0.5

  /// Changes accumulated during debounce period
  private var accumulatedChanges: [LocalChange] = []

  init(context: NSManagedObjectContext) {
    self.context = context
    setupObservers()
  }

  deinit {
    debounceTimer?.invalidate()
  }

  // MARK: - Public API

  /// Pauses observation (call during incoming sync to avoid loops)
  func pause() {
    isPaused = true
    LoggerService.log("Change observer paused", level: .debug, surface: .sync)
  }

  /// Resumes observation
  func resume() {
    isPaused = false
    LoggerService.log("Change observer resumed", level: .debug, surface: .sync)
  }

  /// Clears pending changes (call after successful sync)
  func clearPendingChanges() {
    pendingChanges.removeAll()
    accumulatedChanges.removeAll()
    LoggerService.log("Pending changes cleared", level: .debug, surface: .sync)
  }

  /// Removes specific changes from the queue
  func removeChanges(_ changes: [LocalChange]) {
    let changeSet = Set(changes)
    pendingChanges.removeAll { changeSet.contains($0) }
  }

  /// Marks a specific object as synced (clears its dirty flag)
  func markAsSynced(objectID: NSManagedObjectID) {
    context?.perform { [weak self] in
      guard let object = try? self?.context?.existingObject(with: objectID) else { return }
      if var syncable = object as? ContentfulSyncable {
        syncable.isDirty = false
      }
    }
  }

  // MARK: - Private Setup

  private func setupObservers() {
    // Observe context did save notifications
    NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)
      .sink { [weak self] notification in
        self?.handleContextDidSave(notification)
      }
      .store(in: &cancellables)

    // Also observe object changes for more granular tracking
    NotificationCenter.default.publisher(
      for: .NSManagedObjectContextObjectsDidChange, object: context
    )
    .sink { [weak self] notification in
      self?.handleObjectsDidChange(notification)
    }
    .store(in: &cancellables)
  }

  private func handleContextDidSave(_ notification: Notification) {
    guard !isPaused else { return }
    guard let userInfo = notification.userInfo else { return }

    var changes: [LocalChange] = []

    // Process inserts
    if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
      changes.append(contentsOf: processObjects(insertedObjects, changeType: .insert))
    }

    // Process updates
    if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
      changes.append(contentsOf: processObjects(updatedObjects, changeType: .update))
    }

    // Process deletes
    if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
      changes.append(contentsOf: processObjects(deletedObjects, changeType: .delete))
    }

    if !changes.isEmpty {
      accumulateChanges(changes)
    }
  }

  private func handleObjectsDidChange(_ notification: Notification) {
    // This can be used for more immediate change detection if needed
    // Currently relying on contextDidSave for batched saves
  }

  private func processObjects(
    _ objects: Set<NSManagedObject>,
    changeType: LocalChange.ChangeType
  ) -> [LocalChange] {
    return objects.compactMap { object -> LocalChange? in
      guard let entityName = object.entity.name,
        syncableEntities.contains(entityName)
      else {
        return nil
      }

      // Get the Contentful ID from the object
      let contentfulId: String
      if let idValue = object.value(forKey: "id") as? String {
        contentfulId = idValue
      } else {
        return nil
      }

      return LocalChange(
        objectID: object.objectID,
        entityName: entityName,
        contentfulId: contentfulId,
        changeType: changeType,
        timestamp: Date()
      )
    }
  }

  private func accumulateChanges(_ changes: [LocalChange]) {
    accumulatedChanges.append(contentsOf: changes)

    // Reset debounce timer
    debounceTimer?.invalidate()
    debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) {
      [weak self] _ in
      self?.flushAccumulatedChanges()
    }
  }

  private func flushAccumulatedChanges() {
    guard !accumulatedChanges.isEmpty else { return }

    // Deduplicate changes (keep latest for each object)
    var uniqueChanges: [NSManagedObjectID: LocalChange] = [:]
    for change in accumulatedChanges {
      // For deletes, always keep them
      // For inserts/updates, keep the latest
      if change.changeType == .delete {
        uniqueChanges[change.objectID] = change
      } else if let existing = uniqueChanges[change.objectID] {
        if change.timestamp > existing.timestamp {
          uniqueChanges[change.objectID] = change
        }
      } else {
        uniqueChanges[change.objectID] = change
      }
    }

    let finalChanges = Array(uniqueChanges.values)
    pendingChanges.append(contentsOf: finalChanges)
    accumulatedChanges.removeAll()

    LoggerService.log(
      "Queued \(finalChanges.count) changes for sync",
      level: .debug,
      surface: .sync
    )

    // Post notification for sync service to pick up
    NotificationCenter.default.post(
      name: .localChangesAvailable,
      object: self,
      userInfo: ["changes": finalChanges]
    )
  }
}

// MARK: - Notification Name Extension

extension Notification.Name {
  /// Posted when local changes are ready to be synced
  static let localChangesAvailable = Notification.Name("localChangesAvailable")
}
