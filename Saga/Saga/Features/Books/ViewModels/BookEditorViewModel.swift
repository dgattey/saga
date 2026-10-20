//
//  BookEditorViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI

/// Drives the shared edit/create form. Edits live in `draft` until `save()`, so cancelling
/// leaves Core Data untouched.
@MainActor
final class BookEditorViewModel: ObservableObject {
  enum Mode: Equatable {
    case create
    case edit(NSManagedObjectID)

    var isCreating: Bool { self == .create }
  }

  enum CoverSearchState: Equatable {
    case idle
    case searching
    case notFound
  }

  typealias CoverSearch = @Sendable (_ isbn: String?, _ title: String, _ author: String) async ->
    String?

  @Published var draft: BookDraft
  @Published private(set) var coverSearchState: CoverSearchState = .idle
  @Published private(set) var isSaving = false
  @Published private(set) var hasAttemptedSave = false
  @Published var error: BookMutationError?
  @Published var coverMessage: String?

  let mode: Mode
  /// The synced Contentful cover, shown when there's no local override.
  let syncedCoverURL: URL?
  private let originalDraft: BookDraft
  private let service: BookMutationService
  private let coverSearch: CoverSearch
  private var coverSearchTask: Task<Void, Never>?

  init(
    book: Book?,
    service: BookMutationService,
    coverSearch: @escaping CoverSearch = { isbn, title, author in
      await CoverImageResolver.bestCoverURL(isbn: isbn, title: title, author: author)
    },
    now: Date = Date()
  ) {
    let draft = book.map { BookDraft(book: $0, now: now) } ?? .empty(now: now)
    self.mode = book.map { .edit($0.objectID) } ?? .create
    self.syncedCoverURL = book?.coverImage?.assetURL
    self.draft = draft
    self.originalDraft = draft
    self.service = service
    self.coverSearch = coverSearch
  }

  // MARK: - Derived state

  var hasChanges: Bool { draft != originalDraft }

  /// Validation issues, hidden until the first save attempt so a blank new-book form isn't red.
  var visibleIssues: [BookDraft.Issue] { hasAttemptedSave ? draft.issues : [] }

  var navigationTitle: String { mode.isCreating ? "New Book" : "Edit Book" }

  var previewCoverURL: URL? {
    switch draft.cover {
    case .none:
      return syncedCoverURL
    case .url(let urlString):
      return URL(string: urlString)
    case .image:
      return nil
    }
  }

  var previewImageData: Data? {
    if case .image(let data) = draft.cover { return data }
    return nil
  }

  var hasCustomCover: Bool { !draft.cover.isEmpty }

  /// Shows the normalized ISBN-13 when the typed value differs (e.g. an ISBN-10).
  var normalizedISBNHint: String? {
    guard let isbn = draft.isbn else { return nil }
    let typedDigits = draft.isbnText.filter(\.isNumber)
    let normalized = String(isbn)
    return typedDigits == normalized ? nil : "Saves as ISBN-13 \(normalized)"
  }

  /// Text binding for the cover URL field; local files show as empty.
  var coverURLText: String {
    get {
      guard let urlString = draft.cover.urlString, !CoverImageStore.isLocalCover(urlString) else {
        return ""
      }
      return urlString
    }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      draft.cover = trimmed.isEmpty ? .none : .url(trimmed)
    }
  }

  // MARK: - Cover actions

  /// Runs the default best-cover lookup (OpenLibrary + BookcoverAPI) for the draft's book.
  func searchForCover() {
    coverSearchTask?.cancel()
    let isbn = draft.isbn.map(String.init)
    let title = draft.normalizedTitle
    let author = draft.normalizedAuthor
    guard isbn != nil || !title.isEmpty else {
      coverMessage = "Add a title or ISBN to search for a cover."
      return
    }
    coverMessage = nil
    coverSearchState = .searching
    coverSearchTask = Task { [weak self, coverSearch] in
      let result = await coverSearch(isbn, title, author)
      guard !Task.isCancelled, let self else { return }
      if let result {
        self.draft.cover = .url(result)
        self.coverSearchState = .idle
      } else {
        self.coverSearchState = .notFound
        self.coverMessage = "No cover found. Try dropping or pasting one."
      }
    }
  }

  func applyCoverInput(_ input: CoverInput?) {
    coverSearchTask?.cancel()
    coverSearchState = .idle
    switch input {
    case .remoteURL(let url):
      draft.cover = .url(url.absoluteString)
      coverMessage =
        GoodreadsSyncService.sanitizedCoverImageURL(url.absoluteString) == nil
        ? "This cover stays on this device; its host can't sync to Contentful." : nil
    case .imageData(let data):
      guard CoverImageStore.isImage(data) else {
        coverMessage = CoverImageStoreError.notAnImage.errorDescription
        return
      }
      draft.cover = .image(data)
      coverMessage = nil
    case nil:
      coverMessage = "Nothing to use as a cover. Copy an image or image URL first."
    }
  }

  func pasteCover() {
    applyCoverInput(CoverInput.fromClipboard())
  }

  func importCoverFile(_ result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      applyCoverInput(CoverInput.readFile(at: url).map(CoverInput.imageData))
    case .failure(let error):
      coverMessage = error.localizedDescription
    }
  }

  /// Drops the local override so the book shows its synced cover (or none, for new books).
  func resetCover() {
    coverSearchTask?.cancel()
    coverSearchState = .idle
    coverMessage = nil
    draft.cover = .none
  }

  // MARK: - Save & delete

  /// Validates and saves the draft, then pushes it to Contentful in the background. Returns the
  /// saved book's ID, or `nil` when validation or the save failed.
  func save() async -> NSManagedObjectID? {
    hasAttemptedSave = true
    guard !isSaving, draft.isValid else { return nil }
    guard mode.isCreating || hasChanges else {
      if case .edit(let bookID) = mode { return bookID }
      return nil
    }
    isSaving = true
    defer { isSaving = false }
    do {
      let pending: PendingBookSync
      switch mode {
      case .create:
        pending = try await service.create(from: draft)
      case .edit(let bookID):
        pending = try await service.update(bookID, with: draft)
      }
      Task(priority: .utility) { [service] in
        await service.sync(pending)
      }
      return pending.bookID
    } catch let mutationError as BookMutationError {
      error = mutationError
    } catch {
      self.error = .saveFailed(reason: error.localizedDescription)
    }
    return nil
  }

  /// Deletes the book being edited and pushes the deletion. Returns `true` on success.
  func delete() async -> Bool {
    guard case .edit(let bookID) = mode, !isSaving else { return false }
    isSaving = true
    defer { isSaving = false }
    do {
      let entryID = try await service.delete(bookID)
      Task(priority: .utility) { [service] in
        await service.syncDeletion(id: entryID)
      }
      return true
    } catch let mutationError as BookMutationError {
      error = mutationError
    } catch {
      self.error = .saveFailed(reason: error.localizedDescription)
    }
    return false
  }
}
