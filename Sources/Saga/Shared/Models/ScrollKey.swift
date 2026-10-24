//
//  ScrollKey.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import CoreData
import Foundation

enum ScrollScope: Hashable {
  case home
  case sidebarBooks
  case book(String)

  static func book(_ objectID: NSManagedObjectID) -> ScrollScope {
    .book(objectID.uriRepresentation().absoluteString)
  }
}

struct ScrollKey: Hashable {
  let scope: ScrollScope
  let region: String
  let contextID: UUID?

  init(scope: ScrollScope, region: String, contextID: UUID? = nil) {
    self.scope = scope
    self.region = region
    self.contextID = contextID
  }
}
