//
//  HomeSection.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import Foundation

enum HomeBookSort: String, CaseIterable, Identifiable, Sendable {
  case defaultOrder = "default"
  case byYear = "year"
  case byStatus = "status"
  case byRating = "rating"
  case titleAZ = "title"
  case authorAZ = "author"

  static let storageKey = "home.bookSort"

  var id: Self { self }

  var title: String {
    switch self {
    case .defaultOrder: "Default"
    case .byYear: "By Year"
    case .byStatus: "By Status"
    case .byRating: "By Rating"
    case .titleAZ: "Title A–Z"
    case .authorAZ: "Author A–Z"
    }
  }

  var systemImage: String {
    switch self {
    case .defaultOrder: "clock"
    case .byYear: "calendar"
    case .byStatus: "bookmark"
    case .byRating: "star"
    case .titleAZ: "textformat.abc"
    case .authorAZ: "person"
    }
  }
}

struct HomeSection: Identifiable {
  let id: String
  let title: String?
  let books: [Book]

  var headerText: String? {
    title.map { "\($0) · \(BooksViewModel.bookCountLabel(books.count))" }
  }
}
