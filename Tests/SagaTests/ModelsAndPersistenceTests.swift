//
//  ModelsAndPersistenceTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

@preconcurrency import Contentful
import CoreData
import Foundation
import SwiftUI
import Testing

@testable import Saga

@Suite("Book & Asset Models")
struct ModelsAndPersistenceTests {
  @Test("ReadingStatus derives from explicit status and start/finish dates")
  func readingStatusDerivation() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let finish = Date(timeIntervalSince1970: 1_700_500_000)

    #expect(ReadingStatus.notStarted.rawValue == "notStarted")
    #expect(ReadingStatus.reading.rawValue == "reading")
    #expect(ReadingStatus.read.rawValue == "read")
    #expect(ReadingStatus.notStarted.title == "Want to Read")
    #expect(ReadingStatus.reading.title == "Currently Reading")
    #expect(ReadingStatus.read.title == "Read")

    #expect(ReadingStatus(readDateStarted: nil, readDateFinished: nil) == .notStarted)
    #expect(ReadingStatus(readDateStarted: start, readDateFinished: nil) == .reading)
    #expect(ReadingStatus(readDateStarted: start, readDateFinished: finish) == .read)
    #expect(ReadingStatus(readDateStarted: nil, readDateFinished: finish) == .read)
    #expect(
      ReadingStatus(readingStatusRaw: "read", readDateStarted: nil, readDateFinished: nil) == .read
    )
    #expect(
      ReadingStatus(readingStatusRaw: "notStarted", readDateStarted: nil, readDateFinished: finish)
        == .read
    )
    #expect(
      ReadingStatus(readingStatusRaw: "invalid", readDateStarted: start, readDateFinished: nil)
        == .reading
    )
  }

  @Test("Book.sidebarFetchRequest configures sort descriptors, prefetching, and batch size")
  func sidebarFetchRequestConfiguration() {
    let request = Book.sidebarFetchRequest()
    #expect(request.entityName == "Book")
    #expect(request.fetchBatchSize == 100)
    #expect(request.relationshipKeyPathsForPrefetching == ["coverImage"])
    #expect(request.sortDescriptors?.count == 1)
    #expect(request.sortDescriptors?.first?.key == "readDateStarted")
    #expect(request.sortDescriptors?.first?.ascending == false)
  }

  @Test("Book and Asset persist in-memory and map to a search document")
  @MainActor
  func bookAndAssetPersistenceAndSearchDocument() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let book = try TestCoreDataStack.makeBook(
      in: context,
      id: "book-1",
      title: "Piranesi",
      author: "Susanna Clarke",
      isbn: 9_781_635_575_637,
      rating: 5,
      reviewPlainText: "The House is infinite.\n\nThe Tides are regular.",
      notesPlainText: "Private note: recommended by Sam.",
      coverURLString: "https://example.com/piranesi.jpg"
    )

    #expect(book.readingStatus == .read)
    #expect(book.coverImage?.assetURL == URL(string: "https://example.com/piranesi.jpg"))

    let finishedYear = Calendar.current.component(.year, from: try #require(book.readDateFinished))
    #expect(
      book.searchDocument
        == BookSearchDocument(
          title: "Piranesi",
          author: "Susanna Clarke",
          isbn: "9781635575637",
          review: "The House is infinite.\n\nThe Tides are regular.",
          notes: "Private note: recommended by Sam.",
          rating: 5,
          status: .read,
          year: finishedYear
        ))
  }

  @Test("Asset.linkedContentfulAsset reuses existing assets by ID")
  @MainActor
  func assetLinkedContentfulAssetDeduplication() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let first = try Saga.Asset.linkedContentfulAsset(
      id: "ASSET-1",
      urlString: "https://example.com/Cover.JPG",
      in: context
    )
    try context.save()

    let duplicate = try Saga.Asset.linkedContentfulAsset(
      id: "ASSET-1",
      urlString: "https://example.com/cover.jpg",
      in: context
    )
    #expect(first.objectID == duplicate.objectID)

    let count = try context.count(for: NSFetchRequest<Saga.Asset>(entityName: "Asset"))
    #expect(count == 1)
  }

  @Test(
    "Book.toServerUpsertPayload snapshots fields and filters cover URLs against server allowlist")
  @MainActor
  func bookServerUpsertPayloadAndCoverAllowlist() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let book = try TestCoreDataStack.makeBook(
      in: context,
      id: "book-sync-1",
      title: "  Project   Hail Mary  ",
      author: "  Andy   Weir ",
      isbn: 9_780_593_135_204,
      rating: 5,
      reviewPlainText: "Amaze! Grace and Rocky.",
      notesPlainText: "  Private book club thoughts.  ",
      coverURLString: "https://covers.openlibrary.org/b/isbn/9780593135204-L.jpg"
    )

    let coverAsset = try #require(book.coverImage)

    let payload = try #require(book.toServerUpsertPayload())
    #expect(payload.id == "book-sync-1")
    #expect(payload.title == "Project Hail Mary")
    #expect(payload.author == "Andy Weir")
    #expect(payload.isbn == 9_780_593_135_204)
    #expect(payload.rating == 5)
    #expect(payload.readingStatus == "read")
    #expect(payload.reviewPlainText == "Amaze! Grace and Rocky.")
    #expect(payload.notesPlainText == "Private book club thoughts.")
    #expect(payload.coverAssetId == coverAsset.id)
    #expect(payload.coverImageUrl == nil)

    book.localCoverImageURL = "https://bookcover.longitood.com/cover.jpg"
    let pendingCoverPayload = try #require(book.toServerUpsertPayload())
    #expect(pendingCoverPayload.coverAssetId == nil)
    #expect(pendingCoverPayload.coverImageUrl == "https://bookcover.longitood.com/cover.jpg")

    book.localCoverImageURL = "https://evil.example.com/cover.jpg"
    let disallowedCoverPayload = try #require(book.toServerUpsertPayload())
    #expect(disallowedCoverPayload.coverImageUrl == nil)
    #expect(disallowedCoverPayload.coverAssetId == nil)

    book.localCoverImageURL = "//images.ctfassets.net/space/asset/cover.jpg"
    let protocolRelativeCtfPayload = try #require(book.toServerUpsertPayload())
    #expect(
      protocolRelativeCtfPayload.coverImageUrl
        == "https://images.ctfassets.net/space/asset/cover.jpg"
    )

    book.localCoverImageURL = "file:///tmp/Covers/cover.png"
    let localFilePayload = try #require(book.toServerUpsertPayload())
    #expect(localFilePayload.coverImageUrl == nil)
    #expect(localFilePayload.coverAssetId == nil)

    #expect(
      GoodreadsSyncService.sanitizedCoverImageURL("https://user:pw@covers.openlibrary.org/a.jpg")
        == nil
    )
    #expect(
      GoodreadsSyncService.sanitizedCoverImageURL("https://covers.openlibrary.org:8443/a.jpg")
        == nil
    )
  }

  @Test("BookServerUpsertPayload encodes cleared fields as explicit nulls and omits empty covers")
  func bookServerUpsertPayloadEncodesExplicitNulls() throws {
    let payload = BookServerUpsertPayload(
      id: "NEW-BOOK",
      title: "Piranesi",
      author: "Susanna Clarke",
      isbn: nil,
      rating: nil,
      readingStatus: "notStarted",
      readDateStarted: nil,
      readDateFinished: nil,
      reviewPlainText: nil,
      coverAssetId: nil,
      coverImageUrl: nil
    )
    let data = try JSONEncoder().encode(payload)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["id"] as? String == "NEW-BOOK")
    #expect(object["readingStatus"] as? String == "notStarted")
    #expect(object["rating"] is NSNull)
    #expect(object["readDateStarted"] is NSNull)
    #expect(object["readDateFinished"] is NSNull)
    #expect(object["reviewPlainText"] is NSNull)
    #expect(object["notesPlainText"] is NSNull)
    #expect(object["isbn"] == nil)
    #expect(object["coverAssetId"] == nil)
    #expect(object["coverImageUrl"] == nil)
    #expect(object["coverImageBase64"] == nil)
    #expect(object["coverImageContentType"] == nil)

    let upload = CoverImageUpload(data: Data([0xFF, 0xD8, 0xFF]), contentType: "image/jpeg")
    let uploadPayload = BookServerUpsertPayload(
      id: "NEW-BOOK",
      title: "Piranesi",
      author: "Susanna Clarke",
      isbn: nil,
      rating: nil,
      readingStatus: "read",
      readDateStarted: nil,
      readDateFinished: nil,
      reviewPlainText: nil,
      coverAssetId: "OLD-ASSET",
      coverImageUrl: "https://covers.openlibrary.org/b/id/1-L.jpg"
    ).withCoverUpload(upload)
    let uploadObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(uploadPayload)) as? [String: Any]
    )
    #expect(uploadObject["coverImageBase64"] as? String == "/9j/")
    #expect(uploadObject["coverImageContentType"] as? String == "image/jpeg")
    #expect(uploadObject["coverAssetId"] == nil)
    #expect(uploadObject["coverImageUrl"] == nil)
    #expect(uploadPayload.withoutCoverUpload().coverImageBase64 == nil)
  }

  @Test("GoodreadsSyncService computes deterministic HMAC-SHA256 signatures")
  func goodreadsSyncServiceHMACSignature() {
    let signature = GoodreadsSyncService.computeHMACSignature(
      secret: "test-secret",
      timestamp: "1700000000",
      method: "post",
      pathname: "/api/books/sync",
      rawBodyString: #"{"deleteIds":["book-1"]}"#
    )
    #expect(signature.count == 64)
    #expect(
      signature
        == GoodreadsSyncService.computeHMACSignature(
          secret: "test-secret",
          timestamp: "1700000000",
          method: "POST",
          pathname: "/api/books/sync",
          rawBodyString: #"{"deleteIds":["book-1"]}"#
        )
    )
  }

  @Test("PersistenceService default store is in Application Support and never Documents")
  func persistenceServiceDefaultStoreUsesApplicationSupport() throws {
    let defaultDirectory = NSPersistentContainer.defaultDirectoryURL().standardizedFileURL.path
    let appSupport = try #require(
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ).standardizedFileURL.path
    #expect(defaultDirectory.hasPrefix(appSupport))
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      #expect(!defaultDirectory.hasPrefix(docs.standardizedFileURL.path))
    }
  }

  @Test("PersistenceService syncs, resets syncToken on full re-sync, and preserves data on failure")
  @MainActor
  func persistenceServiceSyncAndReset() async throws {
    let container = TestCoreDataStack.makeContainer()
    let recorder = SyncTokenRecorder()
    let service = PersistenceService(
      container: container,
      spaceId: "space-valid",
      accessToken: "token-valid",
      syncFetcher: { token in
        await recorder.record(token)
        return try Self.makeMockSyncSpace(
          nextSyncToken: token.isEmpty ? "fresh-token" : "delta-token",
          books: token.isEmpty ? [("book-1", "Piranesi"), ("book-2", "Exhalation")] : []
        )
      }
    )

    try await service.syncWithApi()
    try await service.syncWithApi()
    #expect(await recorder.tokens == ["", "fresh-token"])

    _ = try TestCoreDataStack.makeBook(in: container.viewContext, id: "stale-local")
    #expect(try container.viewContext.count(for: Book.sidebarFetchRequest()) == 3)

    try await service.syncWithApi(reset: true)
    #expect(await recorder.tokens == ["", "fresh-token", ""])
    let books = try container.viewContext.fetch(Book.sidebarFetchRequest())
    #expect(Set(books.map(\.id)) == ["book-1", "book-2"])

    let placeholderService = PersistenceService(
      container: container,
      spaceId: "placeholder",
      accessToken: "placeholder"
    )
    await #expect(throws: PersistenceSyncError.missingCredentials) {
      try await placeholderService.syncWithApi(reset: true)
    }
    #expect(try container.viewContext.count(for: Book.sidebarFetchRequest()) == 2)

    let stallingService = PersistenceService(
      container: container,
      spaceId: "space-valid",
      accessToken: "token-valid",
      syncFetcher: { token in
        if !token.isEmpty { try? await Task.sleep(for: .seconds(5)) }
        return try Self.makeMockSyncSpace(
          nextSyncToken: "token",
          books: [("book-restored", "Project Hail Mary")]
        )
      }
    )
    let syncVM = SyncViewModel(controller: stallingService)
    let backgroundSync = Task { await syncVM.sync() }
    for _ in 0..<50 where !syncVM.isSyncing {
      try await Task.sleep(for: .milliseconds(5))
    }
    await syncVM.resetAndSync()
    await backgroundSync.value
    #expect(!syncVM.isSyncing && !syncVM.isResetting)
    let restored = try container.viewContext.fetch(Book.sidebarFetchRequest())
    #expect(restored.map(\.id) == ["book-restored"])
    #expect(restored.first?.readingStatus == .read)
    #expect(restored.first?.readDateFinished == nil)
    #expect(restored.first?.toServerUpsertPayload()?.readingStatus == "read")
  }

  private static func makeMockSyncSpace(
    nextSyncToken: String,
    books: [(id: String, title: String)]
  ) throws -> Contentful.SyncSpace {
    let items: [[String: Any]] = books.map { book in
      [
        "sys": [
          "type": "Entry",
          "id": book.id,
          "createdAt": "2026-01-10T12:00:00.000Z",
          "updatedAt": "2026-01-15T12:00:00.000Z",
          "contentType": ["sys": ["type": "Link", "linkType": "ContentType", "id": "book"]],
        ],
        "fields": [
          "title": ["en-US": book.title],
          "author": ["en-US": "Author"],
          "readingStatus": ["en-US": "read"],
        ],
      ]
    }
    let localeData = Data(
      #"{"sys":{"type":"Locale","id":"en-US"},"code":"en-US","name":"English","default":true}"#.utf8
    )
    let locale = try JSONDecoder().decode(Contentful.Locale.self, from: localeData)
    let decoder = Client(spaceId: "space", accessToken: "token").jsonDecoder
    decoder.update(with: try #require(LocalizationContext(locales: [locale])))
    let nextSyncURL =
      "https://cdn.contentful.com/spaces/space/environments/master/sync?sync_token=\(nextSyncToken)"
    let data = try JSONSerialization.data(withJSONObject: [
      "sys": ["type": "Array"], "items": items, "nextSyncUrl": nextSyncURL,
    ])
    return try decoder.decode(Contentful.SyncSpace.self, from: data)
  }
}

private actor SyncTokenRecorder {
  private(set) var tokens: [String] = []
  func record(_ token: String) {
    tokens.append(token)
  }
}
