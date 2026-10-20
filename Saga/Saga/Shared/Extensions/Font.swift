//
//  Font.swift
//  Saga
//
//  Created by Dylan Gattey on 1/23/26.
//

import SwiftUI

extension Font {
  static var largeTitleBold: Font {
    .largeTitle.weight(.semibold)
  }

  /// Serif display face (New York) for a book's title on its page.
  static var editorialTitle: Font {
    .system(size: 34, weight: .medium, design: .serif)
  }

  static var editorialAuthor: Font {
    .title3
  }

  /// Serif reading face for notes and reviews.
  static var editorialNotes: Font {
    .system(size: 16, design: .serif)
  }

  /// Small caps-style labels above metadata values and section headers.
  static var editorialLabel: Font {
    .caption2.weight(.semibold)
  }
}
