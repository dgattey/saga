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

  static var editorialTitle: Font {
    .system(size: 34, weight: .medium, design: .serif)
  }

  static var editorialAuthor: Font {
    .title3
  }

  static var editorialNotes: Font {
    .system(size: 16, design: .serif)
  }

  static var editorialLabel: Font {
    .caption2.weight(.semibold)
  }
}
