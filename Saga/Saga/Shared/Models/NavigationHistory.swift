//
//  NavigationHistory.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

final class NavigationHistory: ObservableObject {
    @Published private(set) var backStack: [SidebarSelection] = []
    @Published private(set) var forwardStack: [SidebarSelection] = []
    @Published private(set) var lastSelectionChange: SidebarSelection?
    @Published private(set) var lastSelectionChangeWasHistory = false

    private var isHistoryNavigation = false

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func recordSelectionChange(from oldSelection: SidebarSelection?, to newSelection: SidebarSelection?) {
        guard let newSelection else { return }
        lastSelectionChange = newSelection
        lastSelectionChangeWasHistory = isHistoryNavigation

        defer { isHistoryNavigation = false }
        guard !isHistoryNavigation else { return }
        guard let oldSelection, oldSelection != newSelection else { return }

        backStack.append(oldSelection)
        forwardStack.removeAll()

    }

    func goBack(selection: Binding<SidebarSelection?>) {
        guard let previousSelection = backStack.popLast() else { return }
        if let currentSelection = selection.wrappedValue {
            forwardStack.append(currentSelection)
        }
        isHistoryNavigation = true
        selection.wrappedValue = previousSelection
    }

    func goForward(selection: Binding<SidebarSelection?>) {
        guard let nextSelection = forwardStack.popLast() else { return }
        if let currentSelection = selection.wrappedValue {
            backStack.append(currentSelection)
        }
        isHistoryNavigation = true
        selection.wrappedValue = nextSelection
    }

}
