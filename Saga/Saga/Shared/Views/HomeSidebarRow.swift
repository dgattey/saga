//
//  HomeSidebarRow.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct HomeSidebarRow: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Binding var selection: SidebarSelection?
    
    var body: some View {
        Button {
            withAnimation(AppAnimation.selectionSpring) {
                selection = selection?.homeSelectionPreservingLast() ?? .home(lastSelectedBookID: nil)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house")
                    .font(.headline)
                    .imageScale(.medium)
                Text("Home")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .background {
                if selection?.isHome == true {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectionBackgroundColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
        .padding(.top, 8)
    }
    
    private var selectionBackgroundColor: Color {
        switch controlActiveState {
        case .inactive:
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        default:
            return Color(nsColor: .selectedContentBackgroundColor)
        }
    }
}
