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
        if let readDateFinished = book.readDateFinished {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accentForeground, Color.accentColor)
                    .imageScale(.small)
                Text("Finished \(readDateFinished.formatted(date: .abbreviated, time: .omitted))").font(.caption)
            }
        } else if book.readDateStarted != nil {
            Text("Reading").font(.caption)
        } else if book.createdAt != nil {
            Text("On the shelf").font(.caption)
        }
    }
}
