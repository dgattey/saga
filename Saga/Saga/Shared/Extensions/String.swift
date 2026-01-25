//
//  String.swift
//  Saga
//
//  Created by Dylan Gattey on 7/9/25.
//

extension String {
  var cleanedWhitespace: String {
    self.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
