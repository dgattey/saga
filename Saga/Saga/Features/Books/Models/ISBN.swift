//
//  ISBN.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Foundation

/// ISBN parsing that mirrors the server's `parseIsbn13Number` so local and synced values match.
enum ISBN {
  /// Normalizes an ISBN-10 or ISBN-13 (with or without hyphens/spaces) to a 13-digit number.
  static func isbn13(from raw: String) -> Int64? {
    let normalized = raw.uppercased().filter { $0.isNumber || $0 == "X" }
    if normalized.count == 13, normalized.allSatisfy(\.isNumber) {
      return Int64(normalized)
    }
    guard normalized.count == 10,
      normalized.prefix(9).allSatisfy(\.isNumber),
      let last = normalized.last, last.isNumber || last == "X"
    else {
      return nil
    }
    let base = "978" + normalized.prefix(9)
    guard let checkDigit = isbn13CheckDigit(for: base) else { return nil }
    return Int64(base + checkDigit)
  }

  static func isbn13CheckDigit(for twelveDigits: String) -> String? {
    guard twelveDigits.count == 12 else { return nil }
    var sum = 0
    for (index, character) in twelveDigits.enumerated() {
      guard let digit = character.wholeNumberValue else { return nil }
      sum += index.isMultiple(of: 2) ? digit : digit * 3
    }
    return String((10 - (sum % 10)) % 10)
  }
}
