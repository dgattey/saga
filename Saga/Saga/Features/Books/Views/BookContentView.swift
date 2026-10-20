//
//  BookContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI

/// Renders the full version of a book as an editorial page. Edit morphs the same page in place:
/// the cover stays where it is and each field becomes its editable control.
struct BookContentView: View {
  @ObservedObject var book: Book
  /// Called after the book is deleted so the caller can navigate away.
  var onDelete: () -> Void = {}
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(\.scrollContextID) private var scrollContextID
  @Environment(\.coverNamespace) private var coverNamespace
  @EnvironmentObject private var bookNavigationViewModel: BookNavigationViewModel
  @State private var isEditing = false
  @State private var isConfirmingDelete = false
  @State private var deleteError: BookMutationError?

  var body: some View {
    Group {
      if isEditing {
        editor
      } else {
        readView
      }
    }
    .animation(.smooth(duration: 0.25), value: isEditing)
    .botanicalPageBackground()
    .onChange(of: book.objectID) { _, _ in
      isEditing = false
    }
  }

  // MARK: - Modes

  private var editor: some View {
    BookEditorView(
      book: book,
      context: viewContext,
      scrollScope: ScrollScope.book(book.objectID),
      scrollContextID: scrollContextID
    ) { _ in
      isEditing = false
    }
    .id(book.objectID)
    .transition(.opacity)
  }

  private var readView: some View {
    BookEditorialLayout(
      scrollScope: ScrollScope.book(book.objectID),
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
      .toolbar(removing: .title)
    #endif
    .toolbar { readToolbar }
    .confirmationDialog(
      deleteConfirmationTitle,
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Book", role: .destructive, action: deleteBook)
    } message: {
      Text("This removes the book from Saga and from Contentful.")
    }
    .alert(isPresented: isShowingDeleteError, error: deleteError) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.recoverySuggestion ?? "")
    }
  }

  @ToolbarContentBuilder
  private var readToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        isEditing = true
      } label: {
        Label("Edit", systemImage: "pencil")
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

  // MARK: - Cover

  private var cover: some View {
    let coverImageURLText = book.displayCoverURL?.absoluteString ?? "No image URL"
    return
      coverImage
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

  @ViewBuilder
  private var coverImage: some View {
    let size = BookEditorialMetrics.coverSize
    let image = BookCoverImageView(book: book, targetSize: size)
      .frame(width: size.width, height: size.height)
      .physicalCoverShadow()
    if let coverNamespace {
      image
        .matchedGeometryEffect(
          id: book.objectID.uriRepresentation().absoluteString, in: coverNamespace)
    } else {
      image
    }
  }

  // MARK: - Delete

  private var deleteConfirmationTitle: String {
    let title = book.title?.cleanedWhitespace ?? ""
    return title.isEmpty ? "Delete this book?" : "Delete “\(title)”?"
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

  private var isShowingDeleteError: Binding<Bool> {
    Binding(
      get: { deleteError != nil },
      set: { isPresented in
        if !isPresented {
          deleteError = nil
        }
      }
    )
  }
}
