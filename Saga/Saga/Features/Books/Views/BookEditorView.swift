//
//  BookEditorView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI

/// Edits a book in place on its page, or creates a new one, using the same editorial layout as
/// read mode: the cover stays put and each field turns into its editable control where it sits.
/// Edits stay in a draft until Save, so Cancel never touches Core Data.
struct BookEditorView: View {
  enum Outcome: Equatable {
    case cancelled
    case saved(NSManagedObjectID)
  }

  private enum Field: Hashable {
    case title
    case author
    case isbn
    case notes
  }

  private enum MetadataField: Hashable {
    case started
    case finished
    case isbn
  }

  @StateObject private var viewModel: BookEditorViewModel
  @FocusState private var focusedField: Field?
  private let scrollScope: ScrollScope?
  private let scrollContextID: UUID?
  private let onFinish: (Outcome) -> Void

  /// Edits `book`, or creates a new book when `book` is `nil`.
  init(
    book: Book?,
    context: NSManagedObjectContext,
    scrollScope: ScrollScope? = nil,
    scrollContextID: UUID? = nil,
    onFinish: @escaping (Outcome) -> Void
  ) {
    _viewModel = StateObject(
      wrappedValue: BookEditorViewModel(
        book: book,
        service: BookMutationService(context: context)
      )
    )
    self.scrollScope = scrollScope
    self.scrollContextID = scrollContextID
    self.onFinish = onFinish
  }

  var body: some View {
    BookEditorialLayout(scrollScope: scrollScope, scrollContextID: scrollContextID) {
      BookCoverEditor(viewModel: viewModel)
    } details: {
      details
    }
    .tint(Color.botanicalDeepMoss)
    .disabled(viewModel.isSaving)
    .navigationTitle(viewModel.navigationTitle)
    .toolbar { toolbarContent }
    .alert(isPresented: isShowingError, error: viewModel.error) { _ in
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

  // MARK: - Details column

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
      shelfAndRating
        .padding(.top, 14)
      metadataStrip
        .padding(.top, 22)
      validationMessages
      Divider()
        .padding(.vertical, 22)
      notesEditor
    }
  }

  private var shelfAndRating: some View {
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

  // MARK: - Metadata strip

  private var metadataFields: [MetadataField] {
    switch viewModel.draft.status {
    case .notStarted:
      return [.isbn]
    case .reading:
      return [.started, .isbn]
    case .read:
      return [.started, .finished, .isbn]
    }
  }

  private var metadataStrip: some View {
    let fields = metadataFields
    return ViewThatFits(in: .horizontal) {
      EditorialHairlineRow(count: fields.count) { index in
        metadataField(fields[index])
      }
      VStack(alignment: .leading, spacing: 14) {
        ForEach(fields, id: \.self) { field in
          metadataField(field)
        }
      }
    }
  }

  @ViewBuilder
  private func metadataField(_ field: MetadataField) -> some View {
    switch field {
    case .started:
      EditorialLabeledValue(label: "Started") {
        startedControl
      }
    case .finished:
      EditorialLabeledValue(label: "Finished") {
        DatePicker(
          "Finished",
          selection: $viewModel.draft.finishedDate,
          displayedComponents: .date
        )
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

  /// Finished books can skip the start date, so it can be added or removed in place.
  @ViewBuilder
  private var startedControl: some View {
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
          "Started",
          selection: $viewModel.draft.startedDate,
          displayedComponents: .date
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
          Text(hint)
            .foregroundStyle(.secondary)
        }
      }
      .font(.caption)
      .padding(.top, 12)
    }
  }

  // MARK: - Notes

  private var notesEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      EditorialSectionLabel("Notes")
      TextEditor(text: $viewModel.draft.reviewText)
        .font(.editorialNotes)
        .lineSpacing(5)
        .scrollContentBackground(.hidden)
        .focused($focusedField, equals: .notes)
        .frame(minHeight: 180)
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
        .editorialField(isFocused: focusedField == .notes)
        .accessibilityLabel("Notes")
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Cancel") {
        onFinish(.cancelled)
      }
      .keyboardShortcut(.cancelAction)
      .help("Discard changes (Esc)")
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(viewModel.saveButtonTitle) {
        Task {
          if let bookID = await viewModel.save() {
            onFinish(.saved(bookID))
          }
        }
      }
      .keyboardShortcut(.return, modifiers: .command)
      .disabled(!viewModel.canSave)
      .help(viewModel.saveBlockedReason ?? "Save changes (⌘Return)")
    }
  }

  // MARK: - Helpers

  private var isShowingError: Binding<Bool> {
    Binding(
      get: { viewModel.error != nil },
      set: { isPresented in
        if !isPresented {
          viewModel.error = nil
        }
      }
    )
  }
}
