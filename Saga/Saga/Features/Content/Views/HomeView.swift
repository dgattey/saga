//
//  HomeView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI
import CoreData

private struct Constants {
    static let headerPaddingY: CGFloat = 16
    static let backgroundFadeHeight: CGFloat = 140
}

/// Renders the home view with a book grid
struct HomeView: View {
    @EnvironmentObject private var viewModel: BooksViewModel
    @Binding var selection: SidebarSelection?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            section.content
                        } header: {
                            headerPlaceholderView(title: section.title)
                        }
                    }
                }
            }
            .zIndex(0)
            glassOverlayView
                .zIndex(1)
            headerTitleView(title: sections.first?.title ?? "")
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Home")
#if os(macOS)
        .toolbar(removing: .title)
#endif
    }
    
    private var sections: [HomeSection] {
        [
            HomeSection(
                title: "Books",
                content: AnyView(
                    HomeBooksSectionView(selection: $selection)
                )
            )
        ]
    }
    
    private func headerPlaceholderView(title: String) -> some View {
        Text(title)
            .font(.largeTitleBold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, Constants.headerPaddingY)
            .opacity(0)
            .allowsHitTesting(false)
    }

    private func headerTitleView(title: String) -> some View {
        Text(title)
            .font(.largeTitleBold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, Constants.headerPaddingY)
            .allowsHitTesting(false)
    }

    private var glassOverlayView: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(1.0)
            .frame(height: Constants.backgroundFadeHeight)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black.opacity(0.75), location: 0.75),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }
}
