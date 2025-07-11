//
//  SyncSpace.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import CoreData
import ContentfulPersistence

@objc(SyncSpace)
class SyncSpace: NSManagedObject, SyncSpacePersistable {
    @NSManaged var syncToken: String?
    @NSManaged var dbVersion: NSNumber?
}
