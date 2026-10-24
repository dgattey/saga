//
//  NavigationHistory.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct NavigationEntry: Hashable {
  let selection: SidebarSelection
  let scrollContextID: UUID

  init(selection: SidebarSelection, scrollContextID: UUID = UUID()) {
    self.selection = selection
    self.scrollContextID = scrollContextID
  }
}

/// Protocol for objects that want to be notified of navigation changes
@MainActor
protocol NavigationObserver: AnyObject {
  func onNavigationChange(from oldEntry: NavigationEntry?, to newEntry: NavigationEntry?)
}

@MainActor
@Observable
final class NavigationHistory {
  private(set) var backStack: [NavigationEntry] = []
  private(set) var forwardStack: [NavigationEntry] = []
  private(set) var lastSelectionChange: NavigationEntry?
  private(set) var lastSelectionChangeWasHistory = false
  private(set) var lastHomeScrollContextID: UUID?

  /// Observers that get notified of navigation changes
  @ObservationIgnored private var observers: [NavigationObserver] = []

  @ObservationIgnored private var isHistoryNavigation = false

  var canGoBack: Bool { !backStack.isEmpty }
  var canGoForward: Bool { !forwardStack.isEmpty }

  init(initialHomeScrollContextID: UUID? = nil) {
    self.lastHomeScrollContextID = initialHomeScrollContextID
  }

  /// Registers an observer to be notified of navigation changes
  func addObserver(_ observer: NavigationObserver) {
    observers.append(observer)
  }

  /// Handles navigation changes, updating history stacks and notifying observers
  func onNavigationChange(
    from oldEntry: NavigationEntry?, to newEntry: NavigationEntry?
  ) {
    guard let newEntry else { return }
    lastSelectionChange = newEntry
    lastSelectionChangeWasHistory = isHistoryNavigation
    if newEntry.selection.isHome {
      lastHomeScrollContextID = newEntry.scrollContextID
    }

    // Notify all registered observers
    for observer in observers {
      observer.onNavigationChange(from: oldEntry, to: newEntry)
    }

    defer { isHistoryNavigation = false }
    guard !isHistoryNavigation else { return }
    guard let oldEntry, oldEntry != newEntry else { return }

    backStack.append(oldEntry)
    forwardStack.removeAll()
  }

  func goBack(entry: Binding<NavigationEntry?>) {
    guard let previousEntry = backStack.popLast() else { return }
    if let currentEntry = entry.wrappedValue {
      forwardStack.append(currentEntry)
    }
    isHistoryNavigation = true
    entry.wrappedValue = previousEntry
  }

  func goForward(entry: Binding<NavigationEntry?>) {
    guard let nextEntry = forwardStack.popLast() else { return }
    if let currentEntry = entry.wrappedValue {
      backStack.append(currentEntry)
    }
    isHistoryNavigation = true
    entry.wrappedValue = nextEntry
  }

  @MainActor
  func makeHomeEntry(
    currentEntry: NavigationEntry?,
    scrollStore: ScrollPositionStore,
    cloneFromLast: Bool = true
  ) -> NavigationEntry {
    let selection =
      currentEntry?.selection.homeSelectionPreservingLast() ?? .home(lastSelectedBookID: nil)
    let newContextID = UUID()
    if cloneFromLast, let sourceID = lastHomeScrollContextID {
      scrollStore.clonePositions(from: sourceID, to: newContextID, scope: .home)
    }
    lastHomeScrollContextID = newContextID
    return NavigationEntry(selection: selection, scrollContextID: newContextID)
  }
}
