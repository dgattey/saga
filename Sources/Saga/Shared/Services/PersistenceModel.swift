//
//  PersistenceModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

@preconcurrency import ContentfulPersistence

extension PersistenceModel {

  /// All the types of entries we support syncing – add more here when desired
  private static let entryTypes: [EntryPersistable.Type] = [
    Book.self
  ]

  /// The model the entire app should use
  static var shared: PersistenceModel {
    PersistenceModel(
      spaceType: SyncSpace.self,
      assetType: Asset.self,
      entryTypes: entryTypes
    )
  }
}
