//
//  BookStatusView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// A quick status for if a book's been read/shelved/etc
struct BookStatusView: View {
    var book: Book
    
    var body: some View {
        if book.readDateFinished != nil {
            // Already read
            EmptyView()
        } else if book.readDateStarted != nil {
            // Currently reading
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "book.fill")
                Text("Reading")
            }
            .font(.caption)
            .padding(.vertical, 4)
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.bounce, options: .nonRepeating)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .foregroundStyle(.accent.mix(with: .primary, by: 0.2).opacity(0.5))
                    .defaultShadow()
                    .padding(.horizontal, -4)
            }
        } else if book.createdAt != nil {
            // Up next
            EmptyView()
        }
    }
}
