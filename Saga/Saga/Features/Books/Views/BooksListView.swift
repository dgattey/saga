//
//  BooksListView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import CoreData
import SwiftUI

struct BooksListView: View {
  @Environment(\.managedObjectContext) private var viewContext
  @EnvironmentObject private var viewModel: BooksViewModel
  #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
  #endif
  @Binding var entry: NavigationEntry?
  @FetchRequest(
    sortDescriptors: [NSSortDescriptor(keyPath: \Book.readDateStarted, ascending: false)],
    animation: .default
  ) private var books: FetchedResults<Book>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Books")
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.leading, SidebarLayout.headerLeadingPadding)
        .padding(.trailing, SidebarLayout.rowHorizontalPadding)

      PersistentScrollView(scrollKey: ScrollKey(scope: .sidebarBooks, region: "list")) {
        ScrollVelocityReader()
        LazyVStack(alignment: .leading, spacing: 4) {
          if viewModel.filteredBooks.isEmpty, hasActiveSearch {
            Text("No results")
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
              .padding(.trailing, SidebarLayout.rowHorizontalPadding)
              .padding(.leading, SidebarLayout.rowHorizontalPadding + 8)
          } else {
            ForEach(viewModel.filteredBooks, id: \.model.objectID) { result in
              Button {
                guard entry?.selection != .book(result.model.objectID) else { return }
                withAnimation(AppAnimation.selectionSpring) {
                  entry = NavigationEntry(selection: .book(result.model.objectID))
                }
              } label: {
                BookListPreviewView(result: result)
                  .padding(.vertical, 4)
                  .padding(.horizontal, 8)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background {
                    if entry?.selection == .book(result.model.objectID) {
                      RoundedRectangle(cornerRadius: 6)
                        .fill(selectionBackgroundColor)
                    }
                  }
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
              .contextMenu {
                Button("Delete") {
                  deleteBook(result.model)
                }
              }
            }
          }
        }
        .padding(.vertical, 4)
      }
      .scrollVelocityThrottle()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #if os(macOS)
      .frame(minWidth: 200, idealWidth: 300)
    #endif
    .task(id: viewModel.searchModel.searchText) {
      viewModel.performSearch(
        with: books,
        debounce: viewModel.searchModel.searchText.isEmpty ? nil : .milliseconds(200)
      )
    }
    .onChange(of: Array(books)) {
      viewModel.performSearch(with: books, debounce: .milliseconds(150))
    }
    .searchable(
      text: $viewModel.searchModel.searchText,
      placement: .sidebar
    )
    .navigationTitle("All books")
  }

  private var hasActiveSearch: Bool {
    !viewModel.searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func deleteBook(_ book: Book) {
    withAnimation {
      viewContext.delete(book)
      do {
        try viewContext.save()
      } catch {
        let nsError = error as NSError
        fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
      }
    }
  }

  private var selectionBackgroundColor: Color {
    #if os(macOS)
      switch controlActiveState {
      case .inactive:
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
      default:
        return Color(nsColor: .selectedContentBackgroundColor)
      }
    #else
      // iOS fallback: use standard selection-like background
      return Color.accentColor.opacity(0.15)
    #endif
  }
}
