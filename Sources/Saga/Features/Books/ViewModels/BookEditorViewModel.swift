//
//  BookEditorViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI

@MainActor
@Observable
final class BookEditorViewModel {
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
    @Sendable (_ isbn: String?, _ title: String, _ author: String) async -> String?

  var draft: BookDraft
  private(set) var coverSearchState: CoverSearchState = .idle
  private(set) var isSaving = false
  private(set) var hasAttemptedSave = false
  var error: BookMutationError?
  var coverMessage: String?

  let mode: Mode
  let syncedCoverURL: URL?
  private let originalDraft: BookDraft
  private let service: BookMutationService
  private let coverSearch: CoverSearch
  @ObservationIgnored private var coverSearchTask: Task<Void, Never>?
  @ObservationIgnored private var lastCoverLookup: String?

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

  var hasChanges: Bool { draft != originalDraft }

  var visibleIssues: [BookDraft.Issue] {
    hasAttemptedSave
      ? draft.issues
      : draft.issues.filter { $0 != .missingTitle && $0 != .missingAuthor }
  }

  var canSave: Bool { draft.isValid && !isSaving }
  var saveBlockedReason: String? { draft.issues.first?.message }
  var saveButtonTitle: String { mode.isCreating ? "Add Book" : "Save" }
  var navigationTitle: String { mode.isCreating ? "New Book" : "Edit Book" }

  var previewCoverURL: URL? {
    switch draft.cover {
    case .none: syncedCoverURL
    case .url(let urlString): URL(string: urlString)
    case .image: nil
    }
  }

  var previewImageData: Data? {
    if case .image(let data) = draft.cover { return data }
    return nil
  }

  var hasCustomCover: Bool { !draft.cover.isEmpty }

  var normalizedISBNHint: String? {
    guard let isbn = draft.isbn else { return nil }
    let normalized = String(isbn)
    return draft.isbnText.filter(\.isNumber) == normalized
      ? nil : "Saves as ISBN-13 \(normalized)"
  }

  var coverURLText: String {
    guard let urlString = draft.cover.urlString, !CoverImageStore.isLocalCover(urlString) else {
      return ""
    }
    return urlString
  }

  var coverLookupKey: String? {
    if let isbn = draft.isbn { return String(isbn) }
    let title = draft.normalizedTitle
    let author = draft.normalizedAuthor
    return !title.isEmpty && !author.isEmpty ? "\(title)|\(author)" : nil
  }

  func scheduleAutomaticCoverSearch(after delay: Duration = .milliseconds(900)) {
    guard draft.cover.isEmpty, syncedCoverURL == nil, coverSearchState != .searching,
      let key = coverLookupKey, key != lastCoverLookup
    else { return }
    coverSearchTask?.cancel()
    coverSearchTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self, self.coverLookupKey == key, self.draft.cover.isEmpty
      else { return }
      self.searchForCover(isAutomatic: true)
    }
  }

  func searchForCover(isAutomatic: Bool = false) {
    coverSearchTask?.cancel()
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
      Task { [weak self] in
        let data = await Task.detached(priority: .userInitiated) {
          CoverInput.readFile(at: url)
        }.value
        self?.applyCoverInput(data.map(CoverInput.imageData))
      }
    case .failure(let error):
      coverMessage = error.localizedDescription
    }
  }

  func resetCover() {
    coverSearchTask?.cancel()
    coverSearchState = .idle
    coverMessage = nil
    draft.cover = .none
  }

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
      let pending =
        switch mode {
        case .create: try await service.create(from: draft)
        case .edit(let bookID): try await service.update(bookID, with: draft)
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
