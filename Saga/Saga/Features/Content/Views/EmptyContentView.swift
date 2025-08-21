//
//  EmptyContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

/// Shows an empty state for when we have no content
struct EmptyContentView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "list.bullet.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .font(.largeTitle)
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)
                .transition(.symbolEffect(.appear.byLayer))
            Text("Select an item")
                .font(.title2)
        }
    }
}
