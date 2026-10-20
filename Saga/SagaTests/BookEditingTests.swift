//
//  BookEditingTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Saga

@Suite("Book editing, creation, and covers")
struct BookEditingTests {
  // MARK: - Fixtures

  private static let reference = Date(timeIntervalSince1970: 1_760_000_000)

  private static func makeCoverDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "SagaTests-Covers-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private static func pngData(width: Int = 2, height: Int = 3) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

  private static func validDraft() -> BookDraft {
    var draft = BookDraft.empty(now: reference)
    draft.title = "  The   Dispossessed "
    draft.author = " Ursula K.  Le Guin "
    return draft
  }

  private static func makeService(
    context: NSManagedObjectContext,
    coverDirectory: URL = makeCoverDirectory(),
    pushUpsert: @escaping BookMutationService.PushUpsert = { _ in nil }
  ) -> BookMutationService {
    var service = BookMutationService(context: context)
    service.coverDirectory = coverDirectory
    service.pushUpsert = pushUpsert
    service.pushDeletion = { _ in nil }
    return service
  }

  private static func syncResponse(
    id: String,
    coverAssetId: String?,
    coverImageUrl: String? = nil
  ) -> BookServerSyncResponse {
    BookServerSyncResponse(
      ok: true,
      upserted: 1,
      deleted: 0,
      entries: [
        .init(
          id: id,
          action: "updated",
          coverAssetId: coverAssetId,
          coverImageUrl: coverImageUrl
        )
      ],
      error: nil
    )
  }

  // MARK: - ISBN & drafts

  @Test("ISBN normalizes ISBN-10 (including X check digits) and ISBN-13 input")
  func isbnNormalization() {
    #expect(ISBN.isbn13(from: "0-593-13520-2") == 9_780_593_135_204)
    #expect(ISBN.isbn13(from: "978 0 441 47812 5") == 9_780_441_478_125)
    #expect(ISBN.isbn13(from: "080442957X") == 9_780_804_429_573)
    #expect(ISBN.isbn13(from: "12345") == nil)
    #expect(ISBN.isbn13(from: "") == nil)
  }

  @Test("BookDraft defaults new books to Currently Reading as of today")
  func emptyDraftDefaults() {
    let draft = BookDraft.empty(now: Self.reference)
    #expect(draft.status == .reading)
    #expect(draft.readDateStarted == Self.reference)
    #expect(draft.readDateFinished == nil)
    #expect(draft.rating == 0)
    #expect(draft.cover == .none)
    #expect(draft.issues == [.missingTitle, .missingAuthor])
  }

  @Test("BookDraft validates title, author, ISBN, and date order")
  func draftValidation() {
    var draft = Self.validDraft()
    #expect(draft.isValid)

    draft.isbnText = "12345"
    #expect(draft.issues == [.invalidISBN])
    draft.isbnText = "0-593-13520-2"
    #expect(draft.isValid)

    draft.status = .read
    draft.startedDate = Self.reference
    draft.finishedDate = Self.reference.addingTimeInterval(-3 * 86_400)
    #expect(draft.issues == [.finishedBeforeStarted])

    draft.tracksStartDate = false
    #expect(draft.isValid)
    #expect(draft.readDateStarted == nil)
  }

  @Test("BookDraft maps shelves to dates and applies normalized fields to a book")
  @MainActor
  func draftAppliesToBook() throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let book = try TestCoreDataStack.makeBook(in: context)

    var draft = BookDraft(book: book, now: Self.reference)
    #expect(draft.status == .read)
    #expect(draft.rating == 5)
    #expect(draft.cover == .none)

    draft.title = "  Always   Coming Home "
    draft.status = .notStarted
    draft.rating = 0
    draft.isbnText = "0-593-13520-2"
    draft.reviewText = "   "
    draft.apply(to: book)

    #expect(book.title == "Always Coming Home")
    #expect(book.readDateStarted == nil)
    #expect(book.readDateFinished == nil)
    #expect(book.rating == nil)
    #expect(book.isbn?.int64Value == 9_780_593_135_204)
    #expect(book.reviewDescription == nil)
  }

  @Test("ReadingDuration describes finished and in-progress reads")
  func readingDurationText() {
    let start = Self.reference
    let day: TimeInterval = 86_400
    #expect(ReadingDuration.text(started: nil, finished: start) == nil)
    #expect(ReadingDuration.text(started: start, finished: start) == "Finished the same day")
    #expect(ReadingDuration.text(started: start, finished: start + day) == "1 day")
    #expect(ReadingDuration.text(started: start, finished: start + 12 * day) == "12 days")
    #expect(ReadingDuration.text(started: start, finished: nil, now: start) == "Started today")
    #expect(
      ReadingDuration.text(started: start, finished: nil, now: start + 3 * day) == "3 days so far"
    )
  }

  @Test("BookReadDetailsView builds the Started, Finished, Duration, and ISBN strip")
  @MainActor
  func readMetadataEntries() throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let finishedBook = try TestCoreDataStack.makeBook(
      in: context,
      isbn: 9_780_593_135_204,
      readDateStarted: Self.reference,
      readDateFinished: Self.reference.addingTimeInterval(12 * 86_400)
    )
    let entries = BookReadDetailsView.metadataEntries(for: finishedBook)
    #expect(entries.map(\.label) == ["Started", "Finished", "Duration", "ISBN"])
    #expect(entries[2].value == "12 days")
    #expect(entries[3].value == "9780593135204")
    #expect(BookReadDetailsView.rating(for: finishedBook) == 5)

    let shelvedBook = try TestCoreDataStack.makeBook(
      in: context,
      isbn: nil,
      rating: 0,
      readDateStarted: nil,
      readDateFinished: nil
    )
    #expect(BookReadDetailsView.metadataEntries(for: shelvedBook).isEmpty)
    #expect(BookReadDetailsView.rating(for: shelvedBook) == nil)
  }

  // MARK: - Covers

  @Test("CoverImageResolver prefers large BookcoverAPI art, otherwise the larger candidate")
  func coverResolverPreference() {
    let openLibrary = CoverImageCandidate(url: "https://covers.openlibrary.org/a", bytes: 50_000)
    let largeBookcover = CoverImageCandidate(url: "https://bookcover.example/a", bytes: 45_000)
    let tinyBookcover = CoverImageCandidate(url: "https://bookcover.example/b", bytes: 12_000)

    #expect(
      CoverImageResolver.preferredCandidate(openLibrary: openLibrary, bookcover: largeBookcover)?
        .url == largeBookcover.url
    )
    #expect(
      CoverImageResolver.preferredCandidate(openLibrary: openLibrary, bookcover: tinyBookcover)?
        .url == openLibrary.url
    )
    #expect(
      CoverImageResolver.preferredCandidate(openLibrary: nil, bookcover: tinyBookcover)?.url
        == tinyBookcover.url
    )
    #expect(CoverImageResolver.preferredCandidate(openLibrary: nil, bookcover: nil) == nil)
  }

  @Test("CoverImageStore saves images, rejects non-images, and only removes its own files")
  func coverImageStore() throws {
    let directory = Self.makeCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = try CoverImageStore.save(try Self.pngData(), in: directory)
    #expect(fileURL.isFileURL)
    #expect(fileURL.pathExtension == "png")
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    #expect(CoverImageStore.isLocalCover(fileURL.absoluteString))
    #expect(!CoverImageStore.isLocalCover("https://covers.openlibrary.org/a.jpg"))

    #expect(throws: CoverImageStoreError.notAnImage) {
      try CoverImageStore.save(Data("not an image".utf8), in: directory)
    }

    CoverImageStore.remove(fileURL.absoluteString, in: Self.makeCoverDirectory())
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    CoverImageStore.remove(fileURL.absoluteString, in: directory)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
  }

  @Test("CoverInput parses URLs and prefers syncable URLs, then image data")
  func coverInputParsing() throws {
    #expect(
      CoverInput.remoteURL(from: " //covers.openlibrary.org/b/id/1-L.jpg ")?.absoluteString
        == "https://covers.openlibrary.org/b/id/1-L.jpg"
    )
    #expect(CoverInput.remoteURL(from: "file:///tmp/cover.png") == nil)
    #expect(CoverInput.remoteURL(from: "not a url") == nil)

    let syncable = try #require(URL(string: "https://covers.openlibrary.org/b/id/1-L.jpg"))
    let localOnly = try #require(URL(string: "https://example.com/cover.jpg"))
    let data = Data([0x89, 0x50])
    #expect(
      CoverInput.preferred(from: [.remoteURL(localOnly), .imageData(data), .remoteURL(syncable)])
        == .remoteURL(syncable)
    )
    #expect(
      CoverInput.preferred(from: [.remoteURL(localOnly), .imageData(data)]) == .imageData(data)
    )
    #expect(CoverInput.preferred(from: [.remoteURL(localOnly)]) == .remoteURL(localOnly))
    #expect(CoverInput.preferred(from: []) == nil)
  }

  // MARK: - Mutation service

  @Test("BookMutationService creates books with uppercase UUIDs and a sync payload")
  @MainActor
  func mutationServiceCreates() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let service = Self.makeService(context: context)

    var draft = Self.validDraft()
    draft.isbnText = "0-593-13520-2"
    draft.rating = 4
    let pending = try await service.create(from: draft, now: Self.reference)

    let book = try #require(try context.existingObject(with: pending.bookID) as? Book)
    #expect(book.id == book.id.uppercased())
    #expect(UUID(uuidString: book.id) != nil)
    #expect(book.title == "The Dispossessed")
    #expect(book.author == "Ursula K. Le Guin")
    #expect(book.readingStatus == .reading)
    #expect(book.createdAt == Self.reference)
    #expect(!book.objectID.isTemporaryID)

    let payload = try #require(pending.payload)
    #expect(payload.id == book.id)
    #expect(payload.isbn == 9_780_593_135_204)
    #expect(payload.rating == 4)
    #expect(payload.readDateFinished == nil)
  }

  @Test("BookMutationService rejects invalid drafts without touching Core Data")
  @MainActor
  func mutationServiceRejectsInvalidDrafts() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let service = Self.makeService(context: context)

    await #expect(throws: BookMutationError.self) {
      _ = try await service.create(from: .empty(now: Self.reference))
    }
    let count = try context.count(for: NSFetchRequest<Book>(entityName: "Book"))
    #expect(count == 0)
  }

  @Test("BookMutationService stores dropped images locally and replaces old local covers")
  @MainActor
  func mutationServicePersistsLocalCovers() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let directory = Self.makeCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let service = Self.makeService(context: context, coverDirectory: directory)
    let book = try TestCoreDataStack.makeBook(in: context)
    let syncedCover = book.coverImage

    var draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .image(try Self.pngData())
    let pending = try await service.update(book.objectID, with: draft)

    let localCover = try #require(book.localCoverImageURL)
    let localCoverURL = try #require(URL(string: localCover))
    #expect(localCoverURL.isFileURL)
    #expect(book.displayCoverURL == localCoverURL)
    #expect(book.coverImage == syncedCover)
    #expect(pending.payload?.coverImageUrl == nil)

    draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .url("https://covers.openlibrary.org/b/id/1-L.jpg")
    _ = try await service.update(book.objectID, with: draft)
    #expect(book.localCoverImageURL == "https://covers.openlibrary.org/b/id/1-L.jpg")
    #expect(!FileManager.default.fileExists(atPath: localCoverURL.path(percentEncoded: false)))
  }

  @Test("BookMutationService links the uploaded asset after a successful cover sync")
  @MainActor
  func mutationServiceLinksUploadedCover() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let book = try TestCoreDataStack.makeBook(in: context, id: "BOOK-1")
    let service = Self.makeService(context: context) { payload in
      Self.syncResponse(id: payload.id, coverAssetId: "NEW-ASSET")
    }

    var draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .url("https://covers.openlibrary.org/b/id/1-L.jpg")
    let pending = try await service.update(book.objectID, with: draft)
    #expect(pending.payload?.coverImageUrl == "https://covers.openlibrary.org/b/id/1-L.jpg")

    await service.sync(pending)
    #expect(book.localCoverImageURL == nil)
    #expect(book.coverImage?.id == "NEW-ASSET")
    #expect(
      book.displayCoverURL?.absoluteString == "https://covers.openlibrary.org/b/id/1-L.jpg"
    )
  }

  @Test("BookMutationService keeps the local cover when the server didn't upload a new asset")
  @MainActor
  func mutationServiceKeepsCoverWhenUploadFails() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let book = try TestCoreDataStack.makeBook(in: context, id: "BOOK-2")
    let existingAssetID = try #require(book.coverImage?.id)
    let service = Self.makeService(context: context) { payload in
      Self.syncResponse(id: payload.id, coverAssetId: existingAssetID)
    }

    var draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .url("https://covers.openlibrary.org/b/id/2-L.jpg")
    let pending = try await service.update(book.objectID, with: draft)
    await service.sync(pending)
    #expect(book.localCoverImageURL == "https://covers.openlibrary.org/b/id/2-L.jpg")
    #expect(book.coverImage?.id == existingAssetID)
  }

  @Test("CoverImageStore compresses covers to bounded JPEGs for upload")
  func coverImageStoreCompressesUploads() throws {
    let directory = Self.makeCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = try CoverImageStore.save(
      try Self.pngData(width: 2400, height: 3600),
      in: directory
    )

    let upload = try CoverImageStore.uploadData(forCoverAt: fileURL)
    #expect(upload.contentType == "image/jpeg")
    #expect(upload.data.count <= CoverImageStore.maxUploadBytes)
    let source = try #require(CGImageSourceCreateWithData(upload.data as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1600)
    #expect((properties[kCGImagePropertyPixelWidth] as? Int ?? 0) < 1600)

    #expect(throws: CoverImageStoreError.notAnImage) {
      try CoverImageStore.uploadData(forCoverAt: directory.appending(path: "missing.png"))
    }
  }

  @Test("BookMutationService uploads dropped covers as base64 and links the returned asset")
  @MainActor
  func mutationServiceUploadsLocalCover() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let directory = Self.makeCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try TestCoreDataStack.makeBook(in: context, id: "BOOK-4")
    let recorder = PayloadRecorder()
    let assetURL = "https://images.ctfassets.net/space/new-asset/cover.jpg"
    let service = Self.makeService(context: context, coverDirectory: directory) { payload in
      await recorder.record(payload)
      return Self.syncResponse(
        id: payload.id,
        coverAssetId: "UPLOADED",
        coverImageUrl: assetURL
      )
    }

    var draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .image(try Self.pngData())
    let pending = try await service.update(book.objectID, with: draft)
    let fileURL = try #require(pending.coverFileURL)
    #expect(pending.payload?.hasCoverUpload == false)

    await service.sync(pending)
    let sent = try #require(await recorder.payloads.first)
    #expect(sent.coverImageContentType == "image/jpeg")
    let sentImage = try #require(sent.coverImageBase64.flatMap { Data(base64Encoded: $0) })
    #expect(CoverImageStore.isImage(sentImage))
    #expect(sent.coverImageUrl == nil)
    #expect(sent.coverAssetId == nil)
    #expect(book.localCoverImageURL == nil)
    #expect(book.coverImage?.id == "UPLOADED")
    #expect(book.displayCoverURL?.absoluteString == assetURL)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
  }

  @Test("BookMutationService retries without the image when a cover upload fails")
  @MainActor
  func mutationServiceRetriesWithoutFailedUpload() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let directory = Self.makeCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try TestCoreDataStack.makeBook(in: context, id: "BOOK-5")
    let recorder = PayloadRecorder()
    let service = Self.makeService(context: context, coverDirectory: directory) { payload in
      await recorder.record(payload)
      return nil
    }

    var draft = BookDraft(book: book, now: Self.reference)
    draft.cover = .image(try Self.pngData())
    let pending = try await service.update(book.objectID, with: draft)
    await service.sync(pending)

    let sent = await recorder.payloads
    #expect(sent.map(\.hasCoverUpload) == [true, false])
    #expect(book.localCoverImageURL == pending.coverFileURL?.absoluteString)
  }

  @Test("BookMutationService deletes books and returns the Contentful entry ID")
  @MainActor
  func mutationServiceDeletes() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let book = try TestCoreDataStack.makeBook(in: context, id: "BOOK-3")
    let service = Self.makeService(context: context)

    let entryID = try await service.delete(book.objectID)
    #expect(entryID == "BOOK-3")
    let count = try context.count(for: NSFetchRequest<Book>(entityName: "Book"))
    #expect(count == 0)
  }

  // MARK: - Editor view model

  @Test("BookEditorViewModel cancels without saving and saves edits on Done")
  @MainActor
  func editorViewModelEditsBook() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let book = try TestCoreDataStack.makeBook(in: context, title: "Original")
    let viewModel = BookEditorViewModel(
      book: book,
      service: Self.makeService(context: context)
    )
    #expect(viewModel.mode == .edit(book.objectID))
    #expect(viewModel.saveButtonTitle == "Save")
    #expect(!viewModel.hasChanges)

    viewModel.draft.title = "Edited"
    #expect(viewModel.hasChanges)
    #expect(book.title == "Original")

    viewModel.draft.author = " "
    #expect(viewModel.visibleIssues.isEmpty)
    #expect(await viewModel.save() == nil)
    #expect(viewModel.visibleIssues == [.missingAuthor])
    #expect(book.title == "Original")

    viewModel.draft.author = "Someone"
    #expect(await viewModel.save() == book.objectID)
    #expect(book.title == "Edited")
    #expect(book.author == "Someone")
  }

  @Test("BookEditorViewModel creates books and applies cover search and inputs")
  @MainActor
  func editorViewModelCreatesBook() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let viewModel = BookEditorViewModel(
      book: nil,
      service: Self.makeService(context: context),
      coverSearch: { isbn, title, _ in
        isbn == "9780593135204" && title == "Project Hail Mary"
          ? "https://covers.openlibrary.org/b/isbn/9780593135204-L.jpg" : nil
      },
      now: Self.reference
    )
    #expect(viewModel.mode == .create)
    #expect(viewModel.navigationTitle == "New Book")

    viewModel.draft.title = "Project Hail Mary"
    viewModel.draft.author = "Andy Weir"
    viewModel.draft.isbnText = "0593135202"
    #expect(viewModel.normalizedISBNHint == "Saves as ISBN-13 9780593135204")

    viewModel.searchForCover()
    for _ in 0..<50 where viewModel.coverSearchState == .searching {
      try await Task.sleep(for: .milliseconds(10))
    }
    let foundCover = "https://covers.openlibrary.org/b/isbn/9780593135204-L.jpg"
    #expect(viewModel.draft.cover == .url(foundCover))
    #expect(viewModel.coverURLText == foundCover)

    viewModel.applyCoverInput(.imageData(Data("nope".utf8)))
    #expect(viewModel.coverMessage == CoverImageStoreError.notAnImage.errorDescription)
    let png = try Self.pngData()
    viewModel.applyCoverInput(.imageData(png))
    #expect(viewModel.previewImageData == png)
    #expect(viewModel.coverMessage == nil)
    viewModel.resetCover()
    #expect(viewModel.draft.cover == .none)

    let bookID = try #require(await viewModel.save())
    let book = try #require(try context.existingObject(with: bookID) as? Book)
    #expect(book.title == "Project Hail Mary")
    #expect(book.isbn?.int64Value == 9_780_593_135_204)
    #expect(book.readingStatus == .reading)
  }

  @Test("BookEditorViewModel gates Save on valid drafts and validates typed cover URLs")
  @MainActor
  func editorViewModelGatesSaveAndValidatesURLs() throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let viewModel = BookEditorViewModel(
      book: nil,
      service: Self.makeService(context: context),
      now: Self.reference
    )
    #expect(viewModel.saveButtonTitle == "Add Book")
    #expect(!viewModel.canSave)
    #expect(viewModel.saveBlockedReason == "Add a title.")
    #expect(viewModel.visibleIssues.isEmpty)

    viewModel.draft.isbnText = "12345"
    #expect(viewModel.visibleIssues == [.invalidISBN])
    viewModel.draft.isbnText = ""
    viewModel.draft.title = "Piranesi"
    viewModel.draft.author = "Susanna Clarke"
    #expect(viewModel.canSave)
    #expect(viewModel.saveBlockedReason == nil)

    #expect(!viewModel.useCoverURL("not a url"))
    #expect(viewModel.coverMessage == "That isn't a web address. Paste an https:// image link.")
    #expect(viewModel.draft.cover == .none)
    #expect(viewModel.useCoverURL(" //covers.openlibrary.org/b/id/7-L.jpg "))
    #expect(viewModel.draft.cover == .url("https://covers.openlibrary.org/b/id/7-L.jpg"))
    #expect(viewModel.coverMessage == nil)
  }

  @Test("BookEditorViewModel auto-finds a cover once, when there's enough to search with")
  @MainActor
  func editorViewModelAutoFindsCover() async throws {
    let context = TestCoreDataStack.makeContainer().viewContext
    let searches = SearchCounter()
    let foundCover = "https://covers.openlibrary.org/b/id/42-L.jpg"
    let viewModel = BookEditorViewModel(
      book: nil,
      service: Self.makeService(context: context),
      coverSearch: { _, _, _ in
        await searches.increment()
        return foundCover
      },
      now: Self.reference
    )

    viewModel.draft.title = "Piranesi"
    #expect(viewModel.coverLookupKey == nil)
    viewModel.scheduleAutomaticCoverSearch(after: .zero)
    try await Task.sleep(for: .milliseconds(50))
    #expect(await searches.count == 0)

    viewModel.draft.author = " Susanna  Clarke "
    #expect(viewModel.coverLookupKey == "Piranesi|Susanna Clarke")
    viewModel.scheduleAutomaticCoverSearch(after: .zero)
    for _ in 0..<100 where viewModel.draft.cover == .none {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(viewModel.draft.cover == .url(foundCover))
    #expect(await searches.count == 1)

    viewModel.resetCover()
    viewModel.scheduleAutomaticCoverSearch(after: .zero)
    try await Task.sleep(for: .milliseconds(50))
    #expect(viewModel.draft.cover == .none)
    #expect(await searches.count == 1)
  }
}

private actor SearchCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private actor PayloadRecorder {
  private(set) var payloads: [BookServerUpsertPayload] = []
  func record(_ payload: BookServerUpsertPayload) { payloads.append(payload) }
}
