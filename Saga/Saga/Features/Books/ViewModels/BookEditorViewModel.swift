//
//  BookEditorViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI

/// Drives in-place editing and new-book creation on the book page. Edits live in `draft` until
/// `save()`, so cancelling leaves Core Data untouched.
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

  typealias CoverSearch =
    @Sendable (_ isbn: String?, _ title: String, _ author: String) async ->
    String?

  /// The inputs a cover lookup runs with, so the same search isn't repeated automatically.
  struct CoverLookupKey: Equatable {
    let isbn: String?
    let title: String
    let author: String
  }

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
  private var automaticCoverSearchTask: Task<Void, Never>?
  private var lastCoverLookup: CoverLookupKey?

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

  /// Validation issues to show inline. Missing title/author stay hidden until a save attempt so
  /// a blank new book isn't red; the disabled Save button explains them instead.
  var visibleIssues: [BookDraft.Issue] {
    guard !hasAttemptedSave else { return draft.issues }
    return draft.issues.filter { $0 != .missingTitle && $0 != .missingAuthor }
  }

  var canSave: Bool { draft.isValid && !isSaving }

  /// Why Save is disabled, for its help tooltip.
  var saveBlockedReason: String? { draft.issues.first?.message }

  var saveButtonTitle: String { mode.isCreating ? "Add Book" : "Save" }

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

  /// Enough to search for a cover with: a valid ISBN, or both a title and an author.
  var coverLookupKey: CoverLookupKey? {
    let key = CoverLookupKey(
      isbn: draft.isbn.map(String.init),
      title: draft.normalizedTitle,
      author: draft.normalizedAuthor
    )
    guard key.isbn != nil || (!key.title.isEmpty && !key.author.isEmpty) else { return nil }
    return key
  }

  /// Runs the default best-cover lookup (OpenLibrary + BookcoverAPI) for the draft's book.
  func searchForCover() {
    searchForCover(isAutomatic: false)
  }

  /// Looks up a cover on its own after typing pauses, but only while the book has no cover at
  /// all and the details changed since the last lookup.
  func scheduleAutomaticCoverSearch(after delay: Duration = .milliseconds(900)) {
    automaticCoverSearchTask?.cancel()
    guard draft.cover.isEmpty, syncedCoverURL == nil, coverSearchState != .searching,
      let key = coverLookupKey, key != lastCoverLookup
    else {
      return
    }
    automaticCoverSearchTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard let self, self.coverLookupKey == key, self.draft.cover.isEmpty else { return }
      self.searchForCover(isAutomatic: true)
    }
  }

  private func searchForCover(isAutomatic: Bool) {
    coverSearchTask?.cancel()
    automaticCoverSearchTask?.cancel()
    let isbn = draft.isbn.map(String.init)
    let title = draft.normalizedTitle
    let author = draft.normalizedAuthor
    guard isbn != nil || !title.isEmpty else {
      coverMessage = "Add a title or ISBN to search for a cover."
      return
    }
    lastCoverLookup = coverLookupKey
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
        self.coverMessage =
          isAutomatic
          ? "Couldn't find a cover automatically. Drop or paste one."
          : "No cover found. Try dropping or pasting one."
      }
    }
  }

  /// Uses typed text from the URL popover as the cover. Returns `false` (with a message) when
  /// it isn't an `http(s)` URL.
  @discardableResult
  func useCoverURL(_ text: String) -> Bool {
    guard let url = CoverInput.remoteURL(from: text) else {
      coverMessage = "That isn't a web address. Paste an https:// image link."
      return false
    }
    applyCoverInput(.remoteURL(url))
    return true
  }

  func applyCoverInput(_ input: CoverInput?) {
    coverSearchTask?.cancel()
    automaticCoverSearchTask?.cancel()
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
    automaticCoverSearchTask?.cancel()
    coverSearchState = .idle
    coverMessage = nil
    draft.cover = .none
  }

  // MARK: - Save

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
}
