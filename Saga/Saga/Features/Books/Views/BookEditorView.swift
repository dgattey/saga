//
//  BookEditorView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

struct BookEditorView: View {
  enum Outcome: Equatable {
    case cancelled
    case saved(NSManagedObjectID)
  }

  private enum Field: Hashable {
    case title, author, isbn, review, notes
  }

  private enum MetadataField: Hashable {
    case started, finished, isbn
  }

  @State private var viewModel: BookEditorViewModel
  @FocusState private var focusedField: Field?
  private let scrollScope: ScrollScope?
  private let scrollContextID: UUID?
  private let onFinish: (Outcome) -> Void

  init(
    book: Book?,
    context: NSManagedObjectContext,
    scrollScope: ScrollScope? = nil,
    scrollContextID: UUID? = nil,
    onFinish: @escaping (Outcome) -> Void
  ) {
    _viewModel = State(
      initialValue: BookEditorViewModel(book: book, service: BookMutationService(context: context))
    )
    self.scrollScope = scrollScope
    self.scrollContextID = scrollContextID
    self.onFinish = onFinish
  }

  var body: some View {
    VStack(spacing: 0) {
      if viewModel.mode.isCreating {
        HStack(spacing: 10) {
          Text(viewModel.navigationTitle)
            .font(.headline)
          Spacer()
          cancelButton
          saveButton
        }
        .padding(.horizontal, BookEditorialMetrics.outsidePadding)
        .padding(.top, 18)
        .padding(.bottom, 4)
      }
      BookEditorialLayout(scrollScope: scrollScope, scrollContextID: scrollContextID) {
        BookCoverEditor(viewModel: viewModel)
      } details: {
        details
      }
    }
    .tint(Color.botanicalDeepMoss)
    .disabled(viewModel.isSaving)
    .navigationTitle(viewModel.navigationTitle)
    .toolbar {
      if !viewModel.mode.isCreating {
        ToolbarItem(placement: .cancellationAction) { cancelButton }
        ToolbarItem(placement: .confirmationAction) { saveButton }
      }
    }
    .alert(
      isPresented: Binding(
        get: { viewModel.error != nil },
        set: { if !$0 { viewModel.error = nil } }
      ),
      error: viewModel.error
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.recoverySuggestion ?? "")
    }
    .onChange(of: viewModel.coverLookupKey) { _, _ in
      viewModel.scheduleAutomaticCoverSearch()
    }
    .task {
      if viewModel.mode.isCreating {
        focusedField = .title
      }
    }
  }

  // MARK: - Details

  private var details: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Title", text: $viewModel.draft.title, axis: .vertical)
        .font(.editorialTitle)
        .focused($focusedField, equals: .title)
        .editorialField(isFocused: focusedField == .title)
      TextField("Author", text: $viewModel.draft.author)
        .font(.editorialAuthor)
        .foregroundStyle(.secondary)
        .focused($focusedField, equals: .author)
        .editorialField(isFocused: focusedField == .author)
        .padding(.top, 6)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 18) {
          shelfPicker
          ratingControl
        }
        VStack(alignment: .leading, spacing: 12) {
          shelfPicker
          ratingControl
        }
      }
      .padding(.top, 14)
      metadataStrip
        .padding(.top, 22)
      validationMessages
      Divider()
        .padding(.vertical, 22)
      reviewEditor
      Divider()
        .padding(.vertical, 22)
      privateNotesEditor
    }
  }

  private var shelfPicker: some View {
    Picker("Shelf", selection: $viewModel.draft.status.animation(.snappy)) {
      ForEach(ReadingStatus.allCases) { status in
        Text(status.shortTitle).tag(status)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
  }

  private var ratingControl: some View {
    HStack(spacing: 10) {
      StarRatingView(rating: $viewModel.draft.rating, size: 17)
        .accessibilityLabel("Rating")
      if viewModel.draft.rating > 0 {
        Button("Clear") {
          viewModel.draft.rating = 0
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.medium))
      }
    }
  }

  // MARK: - Metadata

  private var metadataStrip: some View {
    let fields: [MetadataField] =
      switch viewModel.draft.status {
      case .notStarted: [.isbn]
      case .reading: [.started, .isbn]
      case .read: [.started, .finished, .isbn]
      }
    return ViewThatFits(in: .horizontal) {
      EditorialHairlineRow(count: fields.count) { metadataField(fields[$0]) }
      VStack(alignment: .leading, spacing: 14) {
        ForEach(fields, id: \.self) { metadataField($0) }
      }
    }
  }

  @ViewBuilder
  private func metadataField(_ field: MetadataField) -> some View {
    switch field {
    case .started:
      EditorialLabeledValue(label: "Started") {
        if viewModel.draft.readDateStarted == nil {
          Button {
            viewModel.draft.tracksStartDate = true
          } label: {
            Label("Add Date", systemImage: "plus.circle")
          }
          .buttonStyle(.borderless)
        } else {
          HStack(spacing: 4) {
            DatePicker(
              "Started", selection: $viewModel.draft.startedDate, displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            if viewModel.draft.status == .read {
              Button {
                viewModel.draft.tracksStartDate = false
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.tertiary)
              }
              .buttonStyle(.borderless)
              .help("Don't track a start date")
              .accessibilityLabel("Remove Start Date")
            }
          }
        }
      }
    case .finished:
      EditorialLabeledValue(label: "Finished") {
        DatePicker("Finished", selection: $viewModel.draft.finishedDate, displayedComponents: .date)
          .datePickerStyle(.compact)
          .labelsHidden()
      }
    case .isbn:
      EditorialLabeledValue(label: "ISBN") {
        TextField("ISBN-10 or 13", text: $viewModel.draft.isbnText)
          .font(.callout.weight(.medium))
          .monospacedDigit()
          .focused($focusedField, equals: .isbn)
          .frame(width: 130)
          .editorialField(isFocused: focusedField == .isbn)
          #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
          #endif
      }
    }
  }

  @ViewBuilder
  private var validationMessages: some View {
    let issues = viewModel.visibleIssues
    let hint = viewModel.normalizedISBNHint
    if !issues.isEmpty || hint != nil {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(issues) { issue in
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.botanicalTerracotta)
        }
        if let hint {
          Text(hint).foregroundStyle(.secondary)
        }
      }
      .font(.caption)
      .padding(.top, 12)
    }
  }

  private var reviewEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      EditorialSectionLabel("Review")
      TextEditor(text: $viewModel.draft.reviewText)
        .font(.editorialNotes)
        .lineSpacing(5)
        .scrollContentBackground(.hidden)
        .focused($focusedField, equals: .review)
        .frame(minHeight: 130)
        .overlay(alignment: .topLeading) {
          if viewModel.draft.reviewText.isEmpty {
            Text("What did you think?")
              .font(.editorialNotes.italic())
              .foregroundStyle(.tertiary)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .padding(.vertical, 6)
        .editorialField(isFocused: focusedField == .review)
        .accessibilityLabel("Review")
    }
  }

  private var privateNotesEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        EditorialSectionLabel("Private Notes", systemImage: "lock.fill")
        Spacer()
        Text("Only visible in Saga")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      TextEditor(text: $viewModel.draft.notesText)
        .font(.editorialNotes)
        .lineSpacing(5)
        .scrollContentBackground(.hidden)
        .focused($focusedField, equals: .notes)
        .frame(minHeight: 140)
        .overlay(alignment: .topLeading) {
          if viewModel.draft.notesText.isEmpty {
            Text("Private notes, quotes, or reminders…")
              .font(.editorialNotes.italic())
              .foregroundStyle(.tertiary)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .padding(.vertical, 6)
        .editorialField(isFocused: focusedField == .notes)
        .accessibilityLabel("Private Notes")
    }
  }

  private var cancelButton: some View {
    Button("Cancel") {
      onFinish(.cancelled)
    }
    .keyboardShortcut(.cancelAction)
    .help("Discard changes (Esc)")
  }

  private var saveButton: some View {
    Button(viewModel.saveButtonTitle) {
      Task {
        if let bookID = await viewModel.save() {
          onFinish(.saved(bookID))
        }
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(Color.botanicalLeaf)
    .keyboardShortcut(.return, modifiers: .command)
    .disabled(!viewModel.canSave)
    .help(viewModel.saveBlockedReason ?? "Save changes (⌘Return)")
  }
}

// MARK: - Cover editor

struct BookCoverEditor: View {
  private static let size = BookEditorialMetrics.coverSize
  private static let cornerRadius = BookEditorialMetrics.coverCornerRadius

  @Bindable var viewModel: BookEditorViewModel
  @State private var isDropTargeted = false
  @State private var isImportingFile = false
  @State private var isShowingURLPopover = false
  @State private var urlText = ""

  var body: some View {
    VStack(spacing: 14) {
      ZStack(alignment: .bottom) {
        coverImage
        BookCoverActionBar(
          isCreating: viewModel.mode.isCreating,
          isSearching: viewModel.coverSearchState == .searching,
          onFind: { viewModel.searchForCover() },
          onPaste: { viewModel.pasteCover() },
          onChooseFile: { isImportingFile = true },
          onEnterURL: {
            urlText = viewModel.coverURLText
            isShowingURLPopover = true
          }
        )
        .popover(isPresented: $isShowingURLPopover, arrowEdge: .bottom) {
          urlPopover
        }
        .padding(8)
      }
      .frame(width: Self.size.width, height: Self.size.height)
      .overlay(alignment: .topTrailing) {
        if viewModel.hasCustomCover {
          Button {
            viewModel.resetCover()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .frame(width: 22, height: 22)
              .glassEffect(.regular.interactive(), in: Circle())
          }
          .buttonStyle(.plain)
          .help(viewModel.mode.isCreating ? "Remove cover" : "Use the synced cover")
          .accessibilityLabel(viewModel.mode.isCreating ? "Remove Cover" : "Use Synced Cover")
          .padding(8)
        }
      }
      .background {
        RoundedRectangle(cornerRadius: Self.cornerRadius + 6, style: .continuous)
          .strokeBorder(
            Color.botanicalLeaf.opacity(isDropTargeted ? 0.95 : 0.35),
            lineWidth: isDropTargeted ? 2.5 : 1.5
          )
          .padding(-6)
      }
      .scaleEffect(isDropTargeted ? 1.02 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDropTargeted)
      .onDrop(of: CoverInput.acceptedTypes, isTargeted: $isDropTargeted) { providers in
        Task { @MainActor in
          viewModel.applyCoverInput(await CoverInput.load(from: providers))
        }
        return true
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Cover image")
      .accessibilityHint("Drop an image or image URL here to use it as the cover")

      Text(viewModel.coverMessage ?? "Drag an image onto the cover to use it.")
        .font(.caption)
        .foregroundStyle(
          viewModel.coverMessage == nil
            ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary
        )
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(width: Self.size.width)
    .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
      viewModel.importCoverFile(result)
    }
  }

  @ViewBuilder
  private var coverImage: some View {
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    if let data = viewModel.previewImageData, let image = Image(coverImageData: data) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay { searchingOverlay }
        .physicalCoverShadow()
    } else if let url = viewModel.previewCoverURL {
      AssetImageView(url: url, targetSize: Self.size)
        .aspectRatio(contentMode: .fill)
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay { searchingOverlay }
        .physicalCoverShadow()
    } else {
      shape
        .fill(Color.botanicalLeaf.opacity(isDropTargeted ? 0.16 : 0.10))
        .overlay {
          shape.strokeBorder(
            Color.botanicalLeaf.opacity(0.75),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
          )
        }
        .overlay {
          VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
              .font(.system(size: 30, weight: .light))
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(Color.botanicalLeaf)
            Text("Drop or Paste Cover")
              .font(.callout.weight(.medium))
            Text("Or find one by title and author")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 56)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay { searchingOverlay }
    }
  }

  @ViewBuilder
  private var searchingOverlay: some View {
    if viewModel.coverSearchState == .searching {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Finding a cover…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
    }
  }

  private var urlPopover: some View {
    let applyURL = {
      if viewModel.useCoverURL(urlText) {
        isShowingURLPopover = false
      }
    }
    return VStack(alignment: .leading, spacing: 10) {
      Text("Cover from URL")
        .font(.headline)
      TextField("https://…", text: $urlText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(applyURL)
        #if os(iOS)
          .textContentType(.URL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif
      HStack {
        Spacer()
        Button("Cancel") { isShowingURLPopover = false }
          .keyboardShortcut(.cancelAction)
        Button("Use Image", action: applyURL)
          .keyboardShortcut(.defaultAction)
          .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(16)
    .tint(Color.botanicalDeepMoss)
  }
}

struct BookCoverActionBar: View {
  let isCreating: Bool
  let isSearching: Bool
  let onFind: () -> Void
  let onPaste: () -> Void
  let onChooseFile: () -> Void
  let onEnterURL: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      action(
        isCreating ? "Auto-Find" : "Find",
        systemImage: "sparkles",
        help: "Find a cover from the title, author, or ISBN",
        action: onFind
      )
      .disabled(isSearching)
      action("Paste", systemImage: "doc.on.clipboard", help: "Paste an image or image URL") {
        onPaste()
      }
      action("File…", systemImage: "folder", help: "Choose an image file") {
        onChooseFile()
      }
      action("URL…", systemImage: "link", help: "Use an image from a web address") {
        onEnterURL()
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .foregroundStyle(.white)
    .background(Capsule().fill(Color.black.opacity(0.62)))
    .glassEffect(.regular, in: Capsule())
    .environment(\.colorScheme, .dark)
  }

  private func action(
    _ title: String,
    systemImage: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .medium))
        Text(title)
          .font(.system(size: 9.5, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(width: 39, height: 34)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

extension Image {
  init?(coverImageData data: Data) {
    #if canImport(AppKit)
      guard let image = NSImage(data: data) else { return nil }
      self.init(nsImage: image)
    #elseif canImport(UIKit)
      guard let image = UIImage(data: data) else { return nil }
      self.init(uiImage: image)
    #endif
  }
}
