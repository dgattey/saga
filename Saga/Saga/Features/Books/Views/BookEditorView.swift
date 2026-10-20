//
//  BookEditorView.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import CoreData
import SwiftUI

/// The shared edit/create form. Edits stay in a draft until Done, so Cancel never touches
/// Core Data.
struct BookEditorView: View {
  enum Outcome: Equatable {
    case cancelled
    case saved(NSManagedObjectID)
    case deleted
  }

  private enum Field: Hashable {
    case title
    case author
    case isbn
  }

  @StateObject private var viewModel: BookEditorViewModel
  @FocusState private var focusedField: Field?
  @State private var isConfirmingDelete = false
  private let onFinish: (Outcome) -> Void

  /// Edits `book`, or creates a new book when `book` is `nil`.
  init(
    book: Book?,
    context: NSManagedObjectContext,
    onFinish: @escaping (Outcome) -> Void
  ) {
    _viewModel = StateObject(
      wrappedValue: BookEditorViewModel(
        book: book,
        service: BookMutationService(context: context)
      )
    )
    self.onFinish = onFinish
  }

  var body: some View {
    Form {
      coverSection
      detailsSection
      readingSection
      ratingSection
      notesSection
      issuesSection
      deleteSection
    }
    .formStyle(.grouped)
    .tint(Color.botanicalDeepMoss)
    .disabled(viewModel.isSaving)
    .navigationTitle(viewModel.navigationTitle)
    .toolbar { toolbarContent }
    .confirmationDialog(
      deleteConfirmationTitle,
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Book", role: .destructive) {
        Task {
          if await viewModel.delete() {
            onFinish(.deleted)
          }
        }
      }
    } message: {
      Text("This removes the book from Saga and from Contentful.")
    }
    .alert(isPresented: isShowingError, error: viewModel.error) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.recoverySuggestion ?? "")
    }
    .task {
      if viewModel.mode.isCreating {
        focusedField = .title
      }
    }
  }

  // MARK: - Sections

  private var coverSection: some View {
    Section("Cover") {
      BookCoverPicker(viewModel: viewModel)
    }
  }

  private var detailsSection: some View {
    Section {
      TextField("Title", text: $viewModel.draft.title)
        .focused($focusedField, equals: .title)
      TextField("Author", text: $viewModel.draft.author)
        .focused($focusedField, equals: .author)
      TextField("ISBN", text: $viewModel.draft.isbnText, prompt: Text("ISBN-10 or ISBN-13"))
        .focused($focusedField, equals: .isbn)
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif
    } header: {
      Text("Details")
    } footer: {
      if let hint = viewModel.normalizedISBNHint {
        Text(hint)
      }
    }
  }

  private var readingSection: some View {
    Section("Reading") {
      Picker("Shelf", selection: $viewModel.draft.status) {
        ForEach(ReadingStatus.allCases) { status in
          Text(status.title).tag(status)
        }
      }
      if viewModel.draft.status == .read {
        Toggle("Track start date", isOn: $viewModel.draft.tracksStartDate)
      }
      if viewModel.draft.readDateStarted != nil {
        DatePicker(
          "Started",
          selection: $viewModel.draft.startedDate,
          displayedComponents: .date
        )
      }
      if viewModel.draft.status == .read {
        DatePicker(
          "Finished",
          selection: $viewModel.draft.finishedDate,
          displayedComponents: .date
        )
      }
    }
  }

  private var ratingSection: some View {
    Section("Rating") {
      LabeledContent("Rating") {
        HStack(spacing: 12) {
          StarRatingView(rating: $viewModel.draft.rating)
          if viewModel.draft.rating > 0 {
            Button("Clear") {
              viewModel.draft.rating = 0
            }
            .buttonStyle(.borderless)
          }
        }
      }
    }
  }

  private var notesSection: some View {
    Section("Notes") {
      TextEditor(text: $viewModel.draft.reviewText)
        .frame(minHeight: 120)
        .accessibilityLabel("Notes")
    }
  }

  @ViewBuilder
  private var issuesSection: some View {
    if !viewModel.visibleIssues.isEmpty {
      Section {
        ForEach(viewModel.visibleIssues) { issue in
          Label(issue.message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.botanicalTerracotta)
        }
      }
    }
  }

  @ViewBuilder
  private var deleteSection: some View {
    if !viewModel.mode.isCreating {
      Section {
        Button("Delete Book…", role: .destructive) {
          isConfirmingDelete = true
        }
      }
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
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(viewModel.mode.isCreating ? "Add Book" : "Done") {
        Task {
          if let bookID = await viewModel.save() {
            onFinish(.saved(bookID))
          }
        }
      }
      .keyboardShortcut(.return, modifiers: .command)
      .disabled(viewModel.isSaving)
    }
  }

  // MARK: - Helpers

  private var deleteConfirmationTitle: String {
    let title = viewModel.draft.normalizedTitle
    return title.isEmpty ? "Delete this book?" : "Delete “\(title)”?"
  }

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
