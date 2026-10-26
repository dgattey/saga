//
//  BookContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

enum BookEditorialMetrics {
  static let coverWidth: CGFloat = 190
  static let coverSize = CGSize(
    width: coverWidth,
    height: coverWidth / BookCoverImageView.coverAspectRatio
  )
  static let coverCornerRadius: CGFloat = 6
  static let columnGap: CGFloat = 40
  static let outsidePadding: CGFloat = 32
  static let maxDetailsWidth: CGFloat = 560
  static let twoColumnThreshold: CGFloat = 600
  static let fieldInset: CGFloat = 8
}

extension ReadingStatus {
  var systemImage: String {
    switch self {
    case .notStarted: "books.vertical"
    case .reading: "bookmark.fill"
    case .read: "checkmark.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .notStarted: .botanicalGold
    case .reading: .botanicalSage
    case .read: .botanicalLeaf
    }
  }
}

enum ReadingDuration {
  static func text(
    started: Date?,
    finished: Date?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String? {
    guard let started else { return nil }
    let isFinished = finished != nil
    let days = max(
      0,
      calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: started),
        to: calendar.startOfDay(for: finished ?? now)
      ).day ?? 0
    )
    return switch days {
    case 0: isFinished ? "Finished the same day" : "Started today"
    case 1: isFinished ? "1 day" : "1 day so far"
    default: isFinished ? "\(days) days" : "\(days) days so far"
    }
  }
}

struct BookContentView: View {
  @ObservedObject var book: Book
  var onDelete: () -> Void = {}
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.scrollContextID) private var scrollContextID
  @Environment(\.coverNamespace) private var coverNamespace
  @Environment(BookNavigationViewModel.self) private var bookNavigationViewModel
  @State private var isEditing = LaunchOptions.initialView == .bookEdit
  @State private var isConfirmingDelete = false
  @State private var deleteError: BookMutationError?

  var body: some View {
    Group {
      if isEditing {
        BookEditorView(
          book: book,
          context: viewContext,
          scrollScope: .book(book.objectID),
          scrollContextID: scrollContextID
        ) { _ in
          isEditing = false
        }
        .id(book.objectID)
        .transition(.opacity)
      } else {
        readView
      }
    }
    .animation(.smooth(duration: 0.25), value: isEditing)
    .botanicalPageBackground()
    #if os(macOS)
      .toolbar(removing: .title)
    #endif
    .onChange(of: book.objectID) { _, _ in
      isEditing = false
    }
  }

  private var readView: some View {
    let title = book.title?.cleanedWhitespace ?? ""
    return BookEditorialLayout(
      scrollScope: .book(book.objectID),
      scrollContextID: scrollContextID
    ) {
      cover
    } details: {
      BookReadDetailsView(book: book)
    }
    .textSelection(.enabled)
    .transition(.opacity)
    .navigationTitle(book.title ?? "Untitled book")
    #if os(macOS)
      .navigationSubtitle(book.author ?? "")
    #else
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isEditing = true
        } label: {
          Label("Edit", systemImage: "pencil")
            .labelStyle(.titleAndIcon)
        }
        .keyboardShortcut("e", modifiers: .command)
        .help("Edit this book (⌘E)")
      }
      ToolbarItem(placement: .primaryAction) {
        Button(role: .destructive) {
          isConfirmingDelete = true
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .help("Delete this book")
      }
    }
    .confirmationDialog(
      title.isEmpty ? "Delete this book?" : "Delete “\(title)”?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Book", role: .destructive, action: deleteBook)
    } message: {
      Text("This removes the book from Saga and from Contentful.")
    }
    .mutationErrorAlert($deleteError)
  }

  private var cover: some View {
    let coverImageURLText = book.displayCoverURL?.absoluteString ?? "No image URL"
    let size = BookEditorialMetrics.coverSize
    let baseImage = BookCoverImageView(book: book, targetSize: size)
      .frame(width: size.width, height: size.height)
      .physicalCoverShadow()
    return Group {
      if let coverNamespace {
        baseImage.matchedGeometryEffect(
          id: book.objectID.uriRepresentation().absoluteString, in: coverNamespace
        )
      } else {
        baseImage
      }
    }
    .rotationEffect(bookNavigationViewModel.coverRotation, anchor: .center)
    .contextMenu {
      CopyButton(labelText: "Copy image URL", value: coverImageURLText)
      if let isbn = book.isbn?.stringValue {
        CopyButton(labelText: "Copy ISBN", value: isbn)
      }
    }
    #if os(macOS)
      .copyable([coverImageURLText])
      .help(coverImageURLText)
    #endif
  }

  private func deleteBook() {
    let service = BookMutationService(context: viewContext)
    let bookID = book.objectID
    Task {
      do {
        let entryID = try await service.delete(bookID)
        onDelete()
        await service.syncDeletion(id: entryID)
      } catch let error as BookMutationError {
        deleteError = error
      } catch {
        deleteError = .saveFailed(reason: error.localizedDescription)
      }
    }
  }
}

struct BookEditorialLayout<Cover: View, Details: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var containerWidth: CGFloat = 0
  private let scrollScope: ScrollScope?
  private let scrollContextID: UUID?
  private let cover: Cover
  private let details: Details

  init(
    scrollScope: ScrollScope? = nil,
    scrollContextID: UUID? = nil,
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder details: () -> Details
  ) {
    self.scrollScope = scrollScope
    self.scrollContextID = scrollContextID
    self.cover = cover()
    self.details = details()
  }

  var body: some View {
    let isCompact =
      horizontalSizeClass == .compact
      || (containerWidth > 0 && containerWidth < BookEditorialMetrics.twoColumnThreshold)
    let content = Group {
      if !isCompact {
        HStack(alignment: .top, spacing: BookEditorialMetrics.columnGap) {
          cover
          details
            .frame(maxWidth: BookEditorialMetrics.maxDetailsWidth, alignment: .topLeading)
        }
      } else {
        VStack(alignment: .leading, spacing: 20) {
          cover.frame(maxWidth: .infinity)
          details
        }
      }
    }
    .padding(isCompact ? 20 : BookEditorialMetrics.outsidePadding)
    .frame(maxWidth: .infinity, alignment: .topLeading)

    Group {
      if let scrollScope {
        PersistentScrollView(
          scrollKey: ScrollKey(scope: scrollScope, region: "page", contextID: scrollContextID)
        ) {
          content
        }
      } else {
        ScrollView(.vertical) { content }
      }
    }
    .scrollEdgeEffectStyle(.soft, for: .top)
    .readSize { size in
      if size.width != containerWidth {
        containerWidth = size.width
      }
    }
  }
}

struct BookMetadataEntry: Identifiable, Equatable {
  let label: String
  let value: String
  var id: String { label }
}

struct BookReadDetailsView: View {
  @ObservedObject var book: Book

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text(book.title ?? "Untitled book")
          .font(.editorialTitle)
          .fixedSize(horizontal: false, vertical: true)
        if let author = book.author?.cleanedWhitespace, !author.isEmpty {
          Text(author)
            .font(.editorialAuthor)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 12) {
          Label(book.readingStatus.title, systemImage: book.readingStatus.systemImage)
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(book.readingStatus.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(book.readingStatus.tint.opacity(0.18), in: Capsule())
          if let rating = Self.rating(for: book) {
            StarRatingView(rating: rating, size: 15)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("\(rating) out of 5 stars")
          }
        }
        .padding(.top, 10)
      }
      let entries = Self.metadataEntries(for: book)
      if !entries.isEmpty {
        ViewThatFits(in: .horizontal) {
          EditorialHairlineRow(count: entries.count) { entryView(entries[$0]) }
          LazyVGrid(
            columns: [
              GridItem(.flexible(), alignment: .leading),
              GridItem(.flexible(), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(entries) { entryView($0) }
          }
        }
        .padding(.top, 18)
      }
      Divider()
        .padding(.vertical, 18)
      if let review = book.reviewDescription, review.nonEmptyPlainText != nil {
        VStack(alignment: .leading, spacing: 10) {
          EditorialSectionLabel("Review")
          AttributedTextViewer(attributedString: review.editorialAttributedString())
        }
        Divider()
          .padding(.vertical, 18)
      }
      if let notes = book.notes, notes.nonEmptyPlainText != nil {
        VStack(alignment: .leading, spacing: 10) {
          EditorialSectionLabel("Private Notes", systemImage: "lock.fill")
          AttributedTextViewer(attributedString: notes.editorialAttributedString())
        }
      } else {
        BookNotesEmptyState()
      }
    }
  }

  private func entryView(_ entry: BookMetadataEntry) -> some View {
    EditorialLabeledValue(label: entry.label) {
      Text(entry.value)
        .font(.callout.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
    }
  }

  static func rating(for book: Book) -> Int? {
    book.validRating
  }

  static func metadataEntries(for book: Book, now: Date = Date()) -> [BookMetadataEntry] {
    var entries: [BookMetadataEntry] = []
    if let started = book.readDateStarted {
      entries.append(
        BookMetadataEntry(
          label: "Started", value: started.formatted(date: .abbreviated, time: .omitted)))
    }
    if let finished = book.readDateFinished {
      entries.append(
        BookMetadataEntry(
          label: "Finished", value: finished.formatted(date: .abbreviated, time: .omitted)))
    }
    if book.readDateFinished != nil || book.readingStatus == .reading,
      let duration = ReadingDuration.text(
        started: book.readDateStarted, finished: book.readDateFinished, now: now
      )
    {
      entries.append(BookMetadataEntry(label: "Duration", value: duration))
    }
    if let isbn = book.isbn?.stringValue {
      entries.append(BookMetadataEntry(label: "ISBN", value: isbn))
    }
    return entries
  }
}

struct EditorialSectionLabel: View {
  private let text: String
  private let systemImage: String?

  init(_ text: String, systemImage: String? = nil) {
    self.text = text
    self.systemImage = systemImage
  }

  var body: some View {
    HStack(spacing: 5) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.caption2.weight(.semibold))
      }
      Text(text.uppercased())
        .font(.editorialLabel)
        .tracking(0.8)
    }
    .foregroundStyle(.secondary)
  }
}

struct EditorialLabeledValue<Value: View>: View {
  let label: String
  @ViewBuilder let value: Value

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      EditorialSectionLabel(label)
      value
    }
  }
}

struct EditorialHairlineRow<Item: View>: View {
  let count: Int
  @ViewBuilder let item: (Int) -> Item

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(0..<count, id: \.self) { index in
        if index > 0 {
          Divider().frame(height: 34)
        }
        item(index)
          .padding(.leading, index == 0 ? 0 : 12)
          .padding(.trailing, index == count - 1 ? 0 : 12)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

struct BookNotesEmptyState: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      EditorialSectionLabel("Private Notes", systemImage: "lock.fill")
      Text("No notes yet. Choose Edit to add your thoughts.")
        .font(.editorialNotes.italic())
        .foregroundStyle(.tertiary)
    }
  }
}

extension View {
  func editorialField(isFocused: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return
      self
      .textFieldStyle(.plain)
      .focusEffectDisabled()
      .padding(.horizontal, BookEditorialMetrics.fieldInset)
      .padding(.vertical, 4)
      .background(shape.fill(Color.primary.opacity(isFocused ? 0.03 : 0.055)))
      .overlay(
        shape.strokeBorder(Color.botanicalLeaf.opacity(isFocused ? 0.85 : 0), lineWidth: 1.5)
      )
      .padding(.horizontal, -BookEditorialMetrics.fieldInset)
      .animation(.easeOut(duration: 0.15), value: isFocused)
  }

  func mutationErrorAlert(_ error: Binding<BookMutationError?>) -> some View {
    alert(
      isPresented: Binding(
        get: { error.wrappedValue != nil },
        set: { if !$0 { error.wrappedValue = nil } }
      ),
      error: error.wrappedValue
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.recoverySuggestion ?? "")
    }
  }
}
