//
//  BookNavigationViewModel.swift
//  Saga
//
//  Created by Dylan Gattey on 1/26/26.
//

import CoreData
import SwiftUI

/// Manages book-specific navigation state, like cover rotation during transitions
final class BookNavigationViewModel: ObservableObject, NavigationObserver {
  @Published var coverRotation: Angle = .zero

  init(navigationHistory: NavigationHistory) {
    navigationHistory.addObserver(self)
  }

  /// Handles navigation changes for book-specific animations
  func onNavigationChange(from oldEntry: NavigationEntry?, to newEntry: NavigationEntry?) {
    guard case .book(let bookID) = newEntry?.selection else { return }

    let targetRotation = rotation(for: bookID)
    withAnimation(AnimationSettings.shared.selectionSpring) {
      coverRotation = targetRotation
    }
  }

  /// Computes the cover rotation angle for a book based on its ID hash
  private func rotation(for bookID: NSManagedObjectID) -> Angle {
    let hash = abs(bookID.hashValue)
    let minDegrees = -1.0
    let maxDegrees = -8.0
    let range = maxDegrees - minDegrees
    let degrees = minDegrees + (Double(hash % 10000) / 10000.0) * range
    return Angle.degrees(degrees)
  }
}
