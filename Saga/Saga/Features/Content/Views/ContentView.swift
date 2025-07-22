//
//  ContentView.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import SwiftUI
import CoreData

struct ContentView: View {

    var body: some View {
        NavigationView {
            BooksListView()
            .toolbar {
                ContentViewToolbar()
            }
            EmptyContentView()
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 300)
#endif
    }
}
