//
//  CoverImageCandidate.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import Foundation

struct CoverImageCandidate {
  static let minimumBytes = 10_000

  let url: String
  let bytes: Int

  static func from(url: URL, minimumBytes: Int = minimumBytes) async throws -> CoverImageCandidate?
  {
    let headRequest = makeHeadRequest(for: url)
    let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
    guard let httpResponse = headResponse as? HTTPURLResponse,
      httpResponse.statusCode != 404
    else {
      return nil
    }
    if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
      let bytes = Int(contentLength)
    {
      guard bytes >= minimumBytes else {
        return nil
      }
      return CoverImageCandidate(url: url.absoluteString, bytes: bytes)
    }
    return CoverImageCandidate(url: url.absoluteString, bytes: 0)
  }

  private static func makeHeadRequest(for url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    return request
  }
}
