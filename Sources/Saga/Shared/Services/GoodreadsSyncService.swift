//
//  GoodreadsSyncService.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import CryptoKit
import Foundation

/// Response returned by `POST /api/books/goodreads-sync`.
struct GoodreadsSyncResponse: Decodable, Sendable {
  let ok: Bool
  let created: Int?
  let updated: Int?
  let unchanged: Int?
  let error: String?
}

struct BookServerUpsertPayload: Encodable, Equatable, Sendable {
  let id: String
  let title: String
  let author: String
  let isbn: Int64?
  let rating: Int?
  let readDateStarted: String?
  let readDateFinished: String?
  let reviewPlainText: String?
  var notesPlainText: String? = nil
  var coverAssetId: String?
  var coverImageUrl: String?
  var coverImageBase64: String? = nil
  var coverImageContentType: String? = nil

  private enum CodingKeys: String, CodingKey {
    case id, title, author, isbn, rating, readDateStarted, readDateFinished
    case reviewPlainText, notesPlainText
    case coverAssetId, coverImageUrl, coverImageBase64, coverImageContentType
  }

  var hasCoverUpload: Bool { coverImageBase64 != nil }

  func withCoverUpload(_ upload: CoverImageUpload) -> BookServerUpsertPayload {
    var copy = self
    copy.coverAssetId = nil
    copy.coverImageUrl = nil
    copy.coverImageBase64 = upload.base64
    copy.coverImageContentType = upload.contentType
    return copy
  }

  func withoutCoverUpload() -> BookServerUpsertPayload {
    var copy = self
    copy.coverImageBase64 = nil
    copy.coverImageContentType = nil
    return copy
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(author, forKey: .author)
    try container.encodeIfPresent(isbn, forKey: .isbn)
    try container.encode(rating, forKey: .rating)
    try container.encode(readDateStarted, forKey: .readDateStarted)
    try container.encode(readDateFinished, forKey: .readDateFinished)
    try container.encode(reviewPlainText, forKey: .reviewPlainText)
    try container.encode(notesPlainText, forKey: .notesPlainText)
    try container.encodeIfPresent(coverAssetId, forKey: .coverAssetId)
    try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
    try container.encodeIfPresent(coverImageBase64, forKey: .coverImageBase64)
    try container.encodeIfPresent(coverImageContentType, forKey: .coverImageContentType)
  }
}

/// Request body sent to `POST /api/books/sync`.
private struct BookServerSyncRequest: Encodable, Sendable {
  let upserts: [BookServerUpsertPayload]?
  let deleteIds: [String]?
}

/// Response returned by `POST /api/books/sync`.
struct BookServerSyncResponse: Decodable, Sendable {
  struct Entry: Decodable, Equatable, Sendable {
    let id: String
    let action: String?
    let coverAssetId: String?
    var coverImageUrl: String? = nil
  }

  let ok: Bool
  let upserted: Int?
  let deleted: Int?
  let entries: [Entry]?
  let error: String?

  func entry(forBookID id: String) -> Entry? {
    entries?.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
  }
}

/// Errors encountered when communicating with `dylangattey.com/api/books/*`.
enum GoodreadsSyncError: LocalizedError {
  case unauthorized
  case serverFailure(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .unauthorized:
      return "Saga server rejected the HMAC/Bearer credentials (HTTP 401)."
    case .serverFailure(let statusCode, let message):
      return "Saga server returned HTTP \(statusCode): \(message)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .unauthorized:
      return "Verify SAGA_API_SECRET in Config.xcconfig matches dylangattey.com."
    case .serverFailure:
      return "Check dylangattey.com Vercel function logs and Contentful Management API credentials."
    }
  }
}

/// Client for `dylangattey.com/api/books/*` endpoints (`POST /api/books/goodreads-sync` and
/// `POST /api/books/sync`), signing requests with `CryptoKit.HMAC<SHA256>`.
enum GoodreadsSyncService {
  static let serverOrigin = "https://dylangattey.com"
  static let goodreadsSyncPath = "/api/books/goodreads-sync"
  static let booksSyncPath = "/api/books/sync"

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 45
    configuration.timeoutIntervalForResource = 90
    return URLSession(configuration: configuration)
  }()

  private static let allowlistedCoverHosts: Set<String> = [
    "covers.openlibrary.org",
    "bookcover.longitood.com",
    "i.gr-assets.com",
    "s.gr-assets.com",
    "images-na.ssl-images-amazon.com",
    "m.media-amazon.com",
    "images.ctfassets.net",
  ]

  private static let maxCoverImageURLLength = 2048

  static func sanitizedCoverImageURL(_ rawURL: String?) -> String? {
    guard let raw = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return nil
    }
    let normalized = raw.hasPrefix("//") ? "https:" + raw : raw
    guard normalized.count <= maxCoverImageURLLength,
      let url = URL(string: normalized),
      url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(),
      allowlistedCoverHosts.contains(host),
      url.user == nil,
      url.password == nil,
      url.port == nil || url.port == 443
    else {
      return nil
    }
    return url.absoluteString
  }

  // MARK: - HMAC-SHA256 Signing

  /// Computes lowercase hex `HMAC-SHA256(key: secret, message: "\(timestamp).\(method).\(pathname).\(rawBodyString)")`.
  static func computeHMACSignature(
    secret: String,
    timestamp: String,
    method: String,
    pathname: String,
    rawBodyString: String
  ) -> String {
    let message = "\(timestamp).\(method.uppercased()).\(pathname).\(rawBodyString)"
    let key = SymmetricKey(data: Data(secret.utf8))
    let authenticationCode = HMAC<SHA256>.authenticationCode(
      for: Data(message.utf8),
      using: key
    )
    return authenticationCode.map { String(format: "%02x", $0) }.joined()
  }

  private static func signedPost<Response: Decodable>(
    path: String,
    secret: String,
    bodyData: Data? = nil,
    errorField: (Response) -> String?
  ) async throws -> Response? {
    guard let url = URL(string: serverOrigin + path) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let rawBodyString: String
    if let bodyData {
      request.httpBody = bodyData
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      rawBodyString = String(data: bodyData, encoding: .utf8) ?? ""
    } else {
      rawBodyString = ""
    }

    let timestamp = String(Int(Date().timeIntervalSince1970))
    let signature = computeHMACSignature(
      secret: secret,
      timestamp: timestamp,
      method: "POST",
      pathname: path,
      rawBodyString: rawBodyString
    )
    request.setValue(timestamp, forHTTPHeaderField: "X-Saga-Timestamp")
    request.setValue(signature, forHTTPHeaderField: "X-Saga-Signature")
    request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GoodreadsSyncError.serverFailure(statusCode: 0, message: "Non-HTTP response")
    }
    if httpResponse.statusCode == 401 {
      throw GoodreadsSyncError.unauthorized
    }

    let decoded: Response?
    do {
      decoded = try JSONDecoder().decode(Response.self, from: data)
    } catch {
      if (200...299).contains(httpResponse.statusCode) {
        LoggerService.log(
          "Failed to decode response from \(path)",
          error: error,
          surface: .sync
        )
      }
      decoded = nil
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message =
        decoded.flatMap(errorField)
        ?? String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw GoodreadsSyncError.serverFailure(statusCode: httpResponse.statusCode, message: message)
    }
    return decoded
  }

  // MARK: - Goodreads RSS Sync (SAG-45)

  /// Triggers `POST /api/books/goodreads-sync` if `SAGA_API_SECRET` is configured.
  /// Logs and swallows errors so Contentful CDA sync always proceeds gracefully.
  @discardableResult
  static func triggerIfConfigured() async -> GoodreadsSyncResponse? {
    guard !PersistenceService.isRunningUnitTests else { return nil }
    let secret = BundleKey.sagaAPISecret.bundleValue
    guard !secret.isEmpty else {
      LoggerService.log(
        "Saga server secret not configured; skipping Goodreads pre-sync trigger",
        level: .debug,
        surface: .sync
      )
      return nil
    }

    do {
      let response: GoodreadsSyncResponse? = try await signedPost(
        path: goodreadsSyncPath,
        secret: secret,
        errorField: \.error
      )
      LoggerService.log(
        "Goodreads sync completed (created: \(response?.created ?? 0), updated: \(response?.updated ?? 0), unchanged: \(response?.unchanged ?? 0))",
        level: .notice,
        surface: .sync
      )
      return response
    } catch {
      LoggerService.log(
        "Goodreads sync webhook failed; continuing with Contentful CDA sync",
        error: error,
        surface: .sync
      )
      return nil
    }
  }

  // MARK: - Local-to-Contentful Book Mutations (SAG-28 / SAG-43)

  /// Pushes a single book upsert to `POST /api/books/sync` if configured.
  @discardableResult
  static func pushBookUpsertIfConfigured(_ payload: BookServerUpsertPayload) async
    -> BookServerSyncResponse?
  {
    await pushBooksSyncIfConfigured(upserts: [payload], deleteIds: [])
  }

  /// Pushes a book deletion to `POST /api/books/sync` if configured.
  @discardableResult
  static func pushBookDeletionIfConfigured(id: String) async -> BookServerSyncResponse? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return await pushBooksSyncIfConfigured(upserts: [], deleteIds: [trimmed])
  }

  @discardableResult
  static func pushBooksSyncIfConfigured(
    upserts: [BookServerUpsertPayload],
    deleteIds: [String]
  ) async -> BookServerSyncResponse? {
    guard !PersistenceService.isRunningUnitTests else { return nil }
    guard !upserts.isEmpty || !deleteIds.isEmpty else { return nil }
    let secret = BundleKey.sagaAPISecret.bundleValue
    guard !secret.isEmpty else {
      LoggerService.log(
        "Saga server secret not configured; skipping remote book mutation sync",
        level: .debug,
        surface: .sync
      )
      return nil
    }

    do {
      let bodyData = try JSONEncoder().encode(
        BookServerSyncRequest(
          upserts: upserts.isEmpty ? nil : upserts,
          deleteIds: deleteIds.isEmpty ? nil : deleteIds
        )
      )
      let response: BookServerSyncResponse? = try await signedPost(
        path: booksSyncPath,
        secret: secret,
        bodyData: bodyData,
        errorField: \.error
      )
      LoggerService.log(
        "Synced book mutations to dylangattey.com (upserted: \(response?.upserted ?? upserts.count), deleted: \(response?.deleted ?? deleteIds.count))",
        level: .notice,
        surface: .sync
      )
      return response
    } catch {
      LoggerService.log(
        "Failed to sync book mutations to dylangattey.com",
        error: error,
        surface: .sync
      )
      return nil
    }
  }
}
