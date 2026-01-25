//
//  SidebarSelection.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import CoreData

enum SidebarSelection: Hashable {
  case home(lastSelectedBookID: NSManagedObjectID?)
  case book(NSManagedObjectID)

  var isHome: Bool {
    if case .home = self {
      return true
    }
    return false
  }

  var matchedBookID: NSManagedObjectID? {
    switch self {
    case .home(let lastSelectedBookID):
      return lastSelectedBookID
    case .book(let bookID):
      return bookID
    }
  }

  func homeSelectionPreservingLast() -> SidebarSelection {
    switch self {
    case .home(let lastSelectedBookID):
      return .home(lastSelectedBookID: lastSelectedBookID)
    case .book(let bookID):
      return .home(lastSelectedBookID: bookID)
    }
  }
}
