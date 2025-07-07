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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.title, ascending: true)],
        animation: .default)
    private var books: FetchedResults<Book>
    
    private func syncFromContentful() {
        PersistenceController.shared.syncWithContentful { result in
            // Optionally show user feedback here
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(books) { book in
                    BookView(book: book)
                }
                .onDelete(perform: deleteBooks)
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addBook) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button(action: syncFromContentful) {
                        Label("Sync", systemImage: "arrow.clockwise")
                    }
                }
            }
            emptyState
        }
    }
    
    private var emptyState: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "list.bullet.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .transition(.symbolEffect(.appear.byLayer))
            
            Text("Select an item")
                .font(.title2)
        }
    }

    private func addBook() {
        withAnimation {
            _ = Book(context: viewContext, title: "Book \(UUID().uuidString)")
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteBooks(offsets: IndexSet) {
        withAnimation {
            offsets.map { books[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
