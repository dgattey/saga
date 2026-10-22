//
//  CreditItem.swift
//  Saga
//
//  Created by Dylan Gattey on 10/15/26.
//

import SwiftUI

/// A quick-action link pill displayed in the About header of Settings.
struct QuickLinkItem: Identifiable, Equatable {
  let id: String
  let title: String
  let systemImage: String
  let url: URL

  static let all: [QuickLinkItem] = [
    QuickLinkItem(
      id: "website",
      title: "Website",
      systemImage: "globe",
      url: URL(staticString: "https://saga.gattey.com")
    ),
    QuickLinkItem(
      id: "github",
      title: "GitHub",
      systemImage: "chevron.left.forwardslash.chevron.right",
      url: URL(staticString: "https://github.com/dgattey/saga")
    ),
    QuickLinkItem(
      id: "author",
      title: "More by Dylan",
      systemImage: "sparkles",
      url: URL(staticString: "https://dylangattey.com")
    ),
  ]
}

/// An attribution entry for an external API, data source, or open-source library.
struct CreditItem: Identifiable, Equatable {
  let id: String
  let name: String
  let version: String?
  let subtitle: String
  let badge: String
  let badgeURL: URL?
  let url: URL
  let systemImage: String
  let tintColor: Color

  static let dataAndAPIs: [CreditItem] = [
    CreditItem(
      id: "open-library",
      name: "Open Library",
      version: nil,
      subtitle: "Book search metadata & ISBN cover images",
      badge: "Open API",
      badgeURL: URL(staticString: "https://openlibrary.org/developers/api"),
      url: URL(staticString: "https://openlibrary.org"),
      systemImage: "books.vertical.fill",
      tintColor: .botanicalLeaf
    ),
    CreditItem(
      id: "bookcover-api",
      name: "Bookcover API",
      version: nil,
      subtitle: "Goodreads cover image resolution by Weslley Araujo",
      badge: "MIT",
      badgeURL: URL(staticString: "https://github.com/w3slley/bookcover-api/blob/main/LICENSE"),
      url: URL(staticString: "https://github.com/w3slley/bookcover-api"),
      systemImage: "book.closed.fill",
      tintColor: .botanicalMoss
    ),
    CreditItem(
      id: "goodreads",
      name: "Goodreads",
      version: nil,
      subtitle: "RSS shelf feed & book metadata import",
      badge: "RSS",
      badgeURL: nil,
      url: URL(staticString: "https://www.goodreads.com"),
      systemImage: "bookmark.fill",
      tintColor: .botanicalGold
    ),
    CreditItem(
      id: "contentful-service",
      name: "Contentful",
      version: nil,
      subtitle: "Cloud content storage & synchronization backend",
      badge: "Sync",
      badgeURL: nil,
      url: URL(staticString: "https://www.contentful.com"),
      systemImage: "icloud.fill",
      tintColor: .botanicalSage
    ),
  ]

  static let openSourceLibraries: [CreditItem] = [
    CreditItem(
      id: "contentful-swift",
      name: "Contentful",
      version: "5.5.15",
      subtitle: "Contentful Content Delivery API SDK",
      badge: "MIT",
      badgeURL: URL(
        staticString: "https://github.com/contentful/contentful.swift/blob/main/LICENSE"),
      url: URL(staticString: "https://github.com/contentful/contentful.swift"),
      systemImage: "shippingbox.fill",
      tintColor: .botanicalLeaf
    ),
    CreditItem(
      id: "contentful-persistence-swift",
      name: "ContentfulPersistence",
      version: "0.18.2",
      subtitle: "Core Data synchronization for Contentful",
      badge: "MIT",
      badgeURL: URL(
        staticString: "https://github.com/contentful/contentful-persistence.swift/blob/main/LICENSE"
      ),
      url: URL(staticString: "https://github.com/contentful/contentful-persistence.swift"),
      systemImage: "arrow.triangle.2.circlepath.circle.fill",
      tintColor: .botanicalSage
    ),
    CreditItem(
      id: "ifrit",
      name: "Ifrit",
      version: "4.0.0",
      subtitle: "Fast fuzzy search for books and authors by Ukushu",
      badge: "MIT",
      badgeURL: URL(staticString: "https://github.com/ukushu/Ifrit/blob/main/LICENSE"),
      url: URL(staticString: "https://github.com/ukushu/Ifrit"),
      systemImage: "magnifyingglass.circle.fill",
      tintColor: .botanicalGold
    ),
    CreditItem(
      id: "sparkle",
      name: "Sparkle",
      version: "2.9.3",
      subtitle: "Automatic software updates for macOS",
      badge: "MIT",
      badgeURL: URL(staticString: "https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE"),
      url: URL(staticString: "https://github.com/sparkle-project/Sparkle"),
      systemImage: "sparkles",
      tintColor: .botanicalMoss
    ),
    CreditItem(
      id: "viewinspector",
      name: "ViewInspector",
      version: "0.10.5",
      subtitle: "SwiftUI view hierarchy inspection & unit testing by Alexey Naumov",
      badge: "MIT",
      badgeURL: URL(staticString: "https://github.com/nalexn/ViewInspector/blob/0.10.5/LICENSE.md"),
      url: URL(staticString: "https://github.com/nalexn/ViewInspector"),
      systemImage: "checkmark.seal.fill",
      tintColor: .botanicalLeaf
    ),
  ]
}

extension URL {
  /// Constructs a URL from a compile-time static string literal without force unwrapping.
  init(staticString: StaticString) {
    guard let url = URL(string: "\(staticString)") else {
      preconditionFailure("Invalid static URL string: \(staticString)")
    }
    self = url
  }
}
