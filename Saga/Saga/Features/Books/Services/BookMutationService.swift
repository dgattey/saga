//
//  BookMutationService.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import Foundation

enum BookMutationError: LocalizedError {
  case invalidDraft([BookDraft.Issue])
  case bookNotFound
  case coverFailed(CoverImageStoreError)
  case saveFailed(reason: String)

  var errorDescription: String? {
    switch self {
    case .invalidDraft(let issues):
      return issues.first?.message ?? "Some fields need attention."
    case .bookNotFound:
      return "This book no longer exists."
    case .coverFailed(let error):
      return error.errorDescription
    case .saveFailed(let reason):
      return "Couldn't save the book: \(reason)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .invalidDraft:
      return "Fix the highlighted fields and save again."
    case .bookNotFound:
      return "It may have been deleted during a sync. Close the editor and refresh."
    case .coverFailed(let error):
      return error.recoverySuggestion
    case .saveFailed:
      return "Try again, or use Clear all local data if the problem persists."
    }
  }
}

/// A locally saved book mutation that still needs pushing to `/api/books/sync`.
struct PendingBookSync: Sendable {
  let bookID: NSManagedObjectID
  let payload: BookServerUpsertPayload?
}

/// Creates, edits, and deletes books in Core Data, then mirrors each change to Contentful
/// through `dylangattey.com/api/books/sync`. Local saves finish first so the UI never waits on
/// the network; call `sync(_:)` afterwards to push.
struct BookMutationService {
  typealias PushUpsert = @Sendable (BookServerUpsertPayload) async -> BookServerSyncResponse?
  typealias PushDeletion = @Sendable (String) async -> BookServerSyncResponse?

  let context: NSManagedObjectContext
  var coverDirectory: URL = CoverImageStore.defaultDirectory
  var pushUpsert: PushUpsert = { payload in
    await GoodreadsSyncService.pushBookUpsertIfConfigured(payload)
  }
  var pushDeletion: PushDeletion = { id in
    await GoodreadsSyncService.pushBookDeletionIfConfigured(id: id)
  }

  // MARK: - Local mutations

  /// Inserts a new book with an uppercase UUID, which the server reuses as the Contentful entry ID.
  func create(from draft: BookDraft, now: Date = Date()) async throws -> PendingBookSync {
    try validate(draft)
    return try await context.perform { [context, coverDirectory] in
      let book = Book(context: context)
      book.id = UUID().uuidString.uppercased()
      book.createdAt = now
      return try Self.save(draft, to: book, in: context, coverDirectory: coverDirectory, now: now)
    }
  }

  func update(
    _ bookID: NSManagedObjectID,
    with draft: BookDraft,
    now: Date = Date()
  ) async throws -> PendingBookSync {
    try validate(draft)
    return try await context.perform { [context, coverDirectory] in
      guard let book = try? context.existingObject(with: bookID) as? Book, !book.isDeleted else {
        throw BookMutationError.bookNotFound
      }
      return try Self.save(draft, to: book, in: context, coverDirectory: coverDirectory, now: now)
    }
  }

  /// Deletes the book locally and returns its Contentful entry ID for `syncDeletion(id:)`.
  func delete(_ bookID: NSManagedObjectID) async throws -> String {
    try await context.perform { [context, coverDirectory] in
      guard let book = try? context.existingObject(with: bookID) as? Book else {
        throw BookMutationError.bookNotFound
      }
      let entryID = book.id
      let localCover = book.localCoverImageURL
      context.delete(book)
      do {
        try context.save()
      } catch {
        context.rollback()
        throw BookMutationError.saveFailed(reason: error.localizedDescription)
      }
      CoverImageStore.remove(localCover, in: coverDirectory)
      return entryID
    }
  }

  // MARK: - Remote sync

  /// Pushes a saved book to Contentful. When the server uploads a pending cover URL as a new
  /// asset, links that asset locally and drops the override so later edits reference it by ID
  /// instead of re-uploading.
  func sync(_ pending: PendingBookSync) async {
    guard let payload = pending.payload,
      let response = await pushUpsert(payload),
      let pushedCoverURL = payload.coverImageUrl,
      let assetID = response.entry(forBookID: payload.id)?.coverAssetId
    else {
      return
    }
    await context.perform { [context] in
      guard let book = try? context.existingObject(with: pending.bookID) as? Book,
        !book.isDeleted,
        GoodreadsSyncService.sanitizedCoverImageURL(book.localCoverImageURL) == pushedCoverURL,
        // The server keeps the old asset ID when an upload fails; keep the override to retry.
        assetID != book.coverImage?.id
      else {
        return
      }
      do {
        book.coverImage = try Asset.linkedContentfulAsset(
          id: assetID,
          urlString: pushedCoverURL,
          in: context
        )
        book.localCoverImageURL = nil
        try context.save()
      } catch {
        context.rollback()
        LoggerService.log(
          "Failed to link uploaded cover asset \(assetID)",
          error: error,
          surface: .persistence
        )
      }
    }
  }

  func syncDeletion(id: String) async {
    _ = await pushDeletion(id)
  }

  // MARK: - Helpers

  private func validate(_ draft: BookDraft) throws {
    let issues = draft.issues
    guard issues.isEmpty else { throw BookMutationError.invalidDraft(issues) }
  }

  /// Must run on `context`'s queue.
  private static func save(
    _ draft: BookDraft,
    to book: Book,
    in context: NSManagedObjectContext,
    coverDirectory: URL,
    now: Date
  ) throws -> PendingBookSync {
    let previousCover = book.localCoverImageURL
    let nextCover: String?
    do {
      nextCover = try coverURLString(for: draft.cover, in: coverDirectory)
    } catch let error as CoverImageStoreError {
      context.rollback()
      throw BookMutationError.coverFailed(error)
    }

    draft.apply(to: book)
    book.localCoverImageURL = nextCover
    book.updatedAt = now
    let payload = book.toServerUpsertPayload()

    do {
      try context.save()
    } catch {
      context.rollback()
      if nextCover != previousCover {
        CoverImageStore.remove(nextCover, in: coverDirectory)
      }
      throw BookMutationError.saveFailed(reason: error.localizedDescription)
    }
    if nextCover != previousCover {
      CoverImageStore.remove(previousCover, in: coverDirectory)
    }
    return PendingBookSync(bookID: book.objectID, payload: payload)
  }

  private static func coverURLString(for cover: CoverDraft, in directory: URL) throws -> String? {
    switch cover {
    case .none:
      return nil
    case .url(let urlString):
      return urlString
    case .image(let data):
      return try CoverImageStore.save(data, in: directory).absoluteString
    }
  }
}
