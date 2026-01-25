//
//  BookStatusView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// A quick status for if a book's been read/shelved/etc
struct BookStatusView: View {
  @ObservedObject var book: Book
  @State private var shouldBounce = false

  var body: some View {
    if book.readingStatus == .reading {
      Image(systemName: "book.circle.fill")
        .font(.title)
        .symbolEffect(.bounce, options: .nonRepeating, value: shouldBounce)
        .foregroundStyle(.secondary)
        .imageScale(.large)
        .defaultShadow()
        .task {
          try? await Task.sleep(for: .seconds(1))
          shouldBounce = true
        }
    } else {
      EmptyView()
    }
  }
}
