//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var syncViewModel: SyncViewModel
    @State private var selectedBookID: NSManagedObjectID?

    var body: some View {
        GoodreadsUploadDropzoneContainer {
            NavigationSplitView(sidebar: {
                BooksListView(selection: $selectedBookID)
            }, detail: {
                if let selectedBookID,
                   let selectedBook = try? viewContext.existingObject(with: selectedBookID) as? Book {
                    BookContentView(book: selectedBook)
                } else {
                    EmptyContentView()
                }
            })
        }
        .symbolRenderingMode(.hierarchical)
        .toolbar {
            ContentViewToolbar()
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: syncViewModel.resetToken) { _ in
            selectedBookID = nil
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 300)
#endif
    }
}
