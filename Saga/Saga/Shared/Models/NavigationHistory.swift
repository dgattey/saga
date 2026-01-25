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
}

final class NavigationHistory: ObservableObject {
  @Published private(set) var backStack: [NavigationEntry] = []
  @Published private(set) var forwardStack: [NavigationEntry] = []
  @Published private(set) var lastSelectionChange: NavigationEntry?
  @Published private(set) var lastSelectionChangeWasHistory = false

  private var isHistoryNavigation = false

  var canGoBack: Bool { !backStack.isEmpty }
  var canGoForward: Bool { !forwardStack.isEmpty }

  func recordSelectionChange(
    from oldEntry: NavigationEntry?, to newEntry: NavigationEntry?
  ) {
    guard let newEntry else { return }
    lastSelectionChange = newEntry
    lastSelectionChangeWasHistory = isHistoryNavigation

    defer { isHistoryNavigation = false }
    guard !isHistoryNavigation else { return }
    guard let oldEntry, oldEntry != newEntry else { return }

    backStack.append(oldEntry)
    forwardStack.removeAll()
  }

  func goBack(
    selection: Binding<SidebarSelection?>,
    scrollContextID: Binding<UUID>,
    previousScrollContextID: Binding<UUID>
  ) {
    guard let previousEntry = backStack.popLast() else { return }
    if let currentSelection = selection.wrappedValue {
      let currentEntry = NavigationEntry(
        selection: currentSelection,
        scrollContextID: scrollContextID.wrappedValue
      )
      forwardStack.append(currentEntry)
    }
    isHistoryNavigation = true
    previousScrollContextID.wrappedValue = scrollContextID.wrappedValue
    scrollContextID.wrappedValue = previousEntry.scrollContextID
    selection.wrappedValue = previousEntry.selection
  }

  func goForward(
    selection: Binding<SidebarSelection?>,
    scrollContextID: Binding<UUID>,
    previousScrollContextID: Binding<UUID>
  ) {
    guard let nextEntry = forwardStack.popLast() else { return }
    if let currentSelection = selection.wrappedValue {
      let currentEntry = NavigationEntry(
        selection: currentSelection,
        scrollContextID: scrollContextID.wrappedValue
      )
      backStack.append(currentEntry)
    }
    isHistoryNavigation = true
    previousScrollContextID.wrappedValue = scrollContextID.wrappedValue
    scrollContextID.wrappedValue = nextEntry.scrollContextID
    selection.wrappedValue = nextEntry.selection
  }
}
