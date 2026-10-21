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
      issues.first?.message ?? "Some fields need attention."
    case .bookNotFound:
      "This book no longer exists."
    case .coverFailed(let error):
      error.errorDescription
    case .saveFailed(let reason):
      "Couldn't save the book: \(reason)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .invalidDraft:
      "Fix the highlighted fields and save again."
    case .bookNotFound:
      "It may have been deleted during a sync. Close the editor and refresh."
    case .coverFailed(let error):
      error.recoverySuggestion
    case .saveFailed:
      "Try again, or use Clear all local data if the problem persists."
    }
  }
}

struct PendingBookSync: Sendable {
  let bookID: NSManagedObjectID
  let payload: BookServerUpsertPayload?
  var coverFileURL: URL? = nil
}

struct BookMutationService {
  typealias PushUpsert = @Sendable (BookServerUpsertPayload) async -> BookServerSyncResponse?
  typealias PushDeletion = @Sendable (String) async -> BookServerSyncResponse?

  let context: NSManagedObjectContext
  var coverDirectory: URL = CoverImageStore.defaultDirectory
  var pushUpsert: PushUpsert = { await GoodreadsSyncService.pushBookUpsertIfConfigured($0) }
  var pushDeletion: PushDeletion = {
    await GoodreadsSyncService.pushBookDeletionIfConfigured(id: $0)
  }

  func create(from draft: BookDraft, now: Date = Date()) async throws -> PendingBookSync {
    guard draft.issues.isEmpty else { throw BookMutationError.invalidDraft(draft.issues) }
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
    guard draft.issues.isEmpty else { throw BookMutationError.invalidDraft(draft.issues) }
    return try await context.perform { [context, coverDirectory] in
      guard let book = try? context.existingObject(with: bookID) as? Book, !book.isDeleted else {
        throw BookMutationError.bookNotFound
      }
      return try Self.save(draft, to: book, in: context, coverDirectory: coverDirectory, now: now)
    }
  }

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

  func sync(_ pending: PendingBookSync) async {
    guard let basePayload = pending.payload else { return }
    let payload: BookServerUpsertPayload = {
      guard let fileURL = pending.coverFileURL, basePayload.coverImageUrl == nil else {
        return basePayload
      }
      do {
        return basePayload.withCoverUpload(try CoverImageStore.uploadData(forCoverAt: fileURL))
      } catch {
        LoggerService.log(
          "Couldn't prepare the local cover for upload; syncing other fields only",
          error: error,
          surface: .sync
        )
        return basePayload
      }
    }()
    let response = await pushUpsert(payload)
    if response == nil, payload.hasCoverUpload {
      _ = await pushUpsert(payload.withoutCoverUpload())
      return
    }
    let pushedCover =
      payload.hasCoverUpload ? pending.coverFileURL?.absoluteString : payload.coverImageUrl
    guard let response,
      let pushedCover,
      let entry = response.entry(forBookID: payload.id),
      let assetID = entry.coverAssetId
    else { return }
    let assetURL = GoodreadsSyncService.sanitizedCoverImageURL(entry.coverImageUrl) ?? pushedCover
    await context.perform { [context, coverDirectory] in
      guard let book = try? context.existingObject(with: pending.bookID) as? Book,
        !book.isDeleted,
        CoverImageStore.isLocalCover(pushedCover)
          ? book.localCoverImageURL == pushedCover
          : GoodreadsSyncService.sanitizedCoverImageURL(book.localCoverImageURL) == pushedCover,
        assetID != book.coverImage?.id
      else { return }
      do {
        book.coverImage = try Asset.linkedContentfulAsset(
          id: assetID, urlString: assetURL, in: context
        )
        book.localCoverImageURL = nil
        try context.save()
      } catch {
        context.rollback()
        LoggerService.log(
          "Failed to link uploaded cover asset \(assetID)", error: error, surface: .persistence
        )
        return
      }
      if assetURL != pushedCover {
        CoverImageStore.remove(pushedCover, in: coverDirectory)
      }
    }
  }

  func syncDeletion(id: String) async {
    _ = await pushDeletion(id)
  }

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
      switch draft.cover {
      case .none: nextCover = nil
      case .url(let urlString): nextCover = urlString
      case .image(let data):
        nextCover = try CoverImageStore.save(data, in: coverDirectory).absoluteString
      }
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
    let coverFileURL = nextCover.flatMap(URL.init(string:)).flatMap { $0.isFileURL ? $0 : nil }
    return PendingBookSync(bookID: book.objectID, payload: payload, coverFileURL: coverFileURL)
  }
}
