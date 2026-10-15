//
//  GoodreadsSyncService.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import CryptoKit
import Foundation

/// Response returned by `GET/POST /api/books/goodreads-sync`.
struct GoodreadsSyncResponse: Decodable, Sendable {
  let ok: Bool
  let dryRun: Bool?
  let scanned: Int?
  let created: Int?
  let updated: Int?
  let unchanged: Int?
  let revalidated: Bool?
  let goodreadsItemsFetched: Int?
  let createdCount: Int?
  let updatedCount: Int?
  let skippedCount: Int?
  let durationMs: Int?
  let error: String?

  var effectiveCreatedCount: Int {
    created ?? createdCount ?? 0
  }

  var effectiveUpdatedCount: Int {
    updated ?? updatedCount ?? 0
  }

  var effectiveSkippedCount: Int {
    unchanged ?? skippedCount ?? 0
  }
}

/// Payload for a single book upsert sent to `POST /api/books/sync`.
struct BookServerUpsertPayload: Encodable, Sendable {
  let id: String
  let title: String
  let author: String
  let isbn: Int64?
  let rating: Int?
  let readDateStarted: String?
  let readDateFinished: String?
  let reviewPlainText: String?
  let coverAssetId: String?
  let coverImageUrl: String?
}

/// Request body sent to `POST /api/books/sync`.
struct BookServerSyncRequest: Encodable, Sendable {
  let upserts: [BookServerUpsertPayload]?
  let deleteIds: [String]?
}

/// Entry metadata returned by `POST /api/books/sync`.
struct BookServerSyncedEntry: Decodable, Sendable {
  let id: String
  let coverAssetId: String?
  let coverImageUrl: String?
}

/// Response returned by `POST /api/books/sync`.
struct BookServerSyncResponse: Decodable, Sendable {
  let ok: Bool
  let upserted: Int?
  let deleted: Int?
  let revalidated: Bool?
  let entries: [BookServerSyncedEntry]?
  let error: String?
}

/// Errors encountered when communicating with `dylangattey.com/api/books/*`.
enum GoodreadsSyncError: LocalizedError {
  case invalidEndpointURL(rawValue: String)
  case missingSecret
  case unauthorized
  case serverFailure(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpointURL(let rawValue):
      return "Invalid Saga server URL: \(rawValue)"
    case .missingSecret:
      return "Saga server API secret is not configured."
    case .unauthorized:
      return "Saga server rejected the HMAC/Bearer credentials (HTTP 401)."
    case .serverFailure(let statusCode, let message):
      return "Saga server returned HTTP \(statusCode): \(message)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .invalidEndpointURL:
      return
        "Verify GOODREADS_SYNC_URL in Config.xcconfig or Settings points to https://dylangattey.com."
    case .missingSecret, .unauthorized:
      return
        "Verify GOODREADS_SYNC_SECRET / SAGA_API_SECRET matches SAGA_API_SECRET or CRON_SECRET on dylangattey.com."
    case .serverFailure:
      return "Check dylangattey.com Vercel function logs and Contentful Management API credentials."
    }
  }
}

/// Client for `dylangattey.com/api/books/*` endpoints (`GET/POST /api/books/goodreads-sync` and
/// `POST /api/books/sync`), signing requests with `CryptoKit.HMAC<SHA256>` (`hmac_with_bearer_fallback`).
typealias SagaServerService = GoodreadsSyncService

enum GoodreadsSyncService {
  static let defaultServerOrigin = "https://dylangattey.com"
  static let goodreadsSyncPath = "/api/books/goodreads-sync"
  static let booksSyncPath = "/api/books/sync"
  static let maxBatchUpsertSize = 100

  static let syncURLStorageKey = "goodreadsSyncURLOverride"
  static let syncSecretStorageKey = "goodreadsSyncSecretOverride"

  private static var configuredBundleURLString: String {
    let sagaServerURL = BundleKey.sagaServerURL.bundleValue
    if !sagaServerURL.isEmpty {
      return sagaServerURL
    }
    return BundleKey.goodreadsSyncURL.bundleValue
  }

  private static var configuredBundleSecret: String {
    let sagaAPISecret = BundleKey.sagaAPISecret.bundleValue
    if !sagaAPISecret.isEmpty {
      return sagaAPISecret
    }
    return BundleKey.goodreadsSyncSecret.bundleValue
  }

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

  /// Returns the configured URL string (UserDefaults override -> Info.plist -> `https://dylangattey.com/api/books/goodreads-sync`).
  static var configuredSyncURLString: String {
    let override =
      UserDefaults.standard.string(forKey: syncURLStorageKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty {
      return resolvedEndpointURL(from: override, defaultPath: goodreadsSyncPath)?.absoluteString
        ?? override
    }
    let bundleURL = configuredBundleURLString
    if !bundleURL.isEmpty {
      return resolvedEndpointURL(from: bundleURL, defaultPath: goodreadsSyncPath)?.absoluteString
        ?? bundleURL
    }
    return defaultServerOrigin + goodreadsSyncPath
  }

  /// Returns the resolved `POST /api/books/sync` endpoint URL string.
  static var configuredBooksMutationURLString: String {
    let override =
      UserDefaults.standard.string(forKey: syncURLStorageKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let baseCandidate = !override.isEmpty ? override : configuredBundleURLString
    let origin = resolvedOrigin(from: baseCandidate) ?? defaultServerOrigin
    return origin + booksSyncPath
  }

  /// Returns the active API secret (UserDefaults override if non-empty, otherwise `SagaAPISecret` / `GoodreadsSyncSecret`).
  static var configuredSyncSecret: String {
    let override =
      UserDefaults.standard.string(forKey: syncSecretStorageKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty {
      return override
    }
    return configuredBundleSecret
  }

  static var isConfigured: Bool {
    !configuredSyncSecret.isEmpty
  }

  /// Formats a `Date` as an ISO-8601 UTC string (`yyyy-MM-dd'T'HH:mm:ss'Z'`).
  static func isoDateString(from date: Date?) -> String? {
    guard let date else { return nil }
    return date.ISO8601Format()
  }

  /// Filters cover URLs to `https:` URLs matching the server's allowlisted cover hosts.
  static func sanitizedCoverImageURL(_ rawURL: String?) -> String? {
    guard let raw = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return nil
    }
    let normalized = raw.hasPrefix("//") ? "https:" + raw : raw
    guard let url = URL(string: normalized),
      url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(),
      allowlistedCoverHosts.contains(host)
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

  private static func signedRequest(
    url: URL,
    method: String,
    bodyData: Data?,
    secret: String
  ) -> URLRequest {
    var request = URLRequest(url: url)
    let upperMethod = method.uppercased()
    request.httpMethod = upperMethod
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let rawBodyString: String
    if let bodyData {
      request.httpBody = bodyData
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      rawBodyString = String(data: bodyData, encoding: .utf8) ?? ""
    } else {
      rawBodyString = ""
    }

    if !secret.isEmpty {
      let timestamp = String(Int(Date().timeIntervalSince1970))
      let pathname = url.path.isEmpty ? "/" : url.path
      let signature = computeHMACSignature(
        secret: secret,
        timestamp: timestamp,
        method: upperMethod,
        pathname: pathname,
        rawBodyString: rawBodyString
      )
      request.setValue(timestamp, forHTTPHeaderField: "X-Saga-Timestamp")
      request.setValue(signature, forHTTPHeaderField: "X-Saga-Signature")
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    return request
  }

  // MARK: - Goodreads RSS Sync (SAG-45)

  /// Triggers `POST /api/books/goodreads-sync` if a secret is configured.
  /// Logs and swallows errors so Contentful CDA sync always proceeds gracefully.
  @discardableResult
  static func triggerIfConfigured() async -> GoodreadsSyncResponse? {
    let secret = configuredSyncSecret
    guard !secret.isEmpty else {
      LoggerService.log(
        "Saga server secret not configured; skipping Goodreads pre-sync trigger",
        level: .debug,
        surface: .sync
      )
      return nil
    }

    let rawURL = configuredSyncURLString
    do {
      let response = try await trigger(urlString: rawURL, secret: secret)
      let created = response.effectiveCreatedCount
      let updated = response.effectiveUpdatedCount
      let skipped = response.effectiveSkippedCount
      LoggerService.log(
        "Goodreads sync completed (created: \(created), updated: \(updated), unchanged: \(skipped))",
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

  /// Executes the signed HTTP POST request to the Goodreads sync endpoint.
  static func trigger(urlString: String, secret: String) async throws -> GoodreadsSyncResponse {
    guard let url = resolvedEndpointURL(from: urlString, defaultPath: goodreadsSyncPath) else {
      throw GoodreadsSyncError.invalidEndpointURL(rawValue: urlString)
    }

    let request = signedRequest(
      url: url,
      method: "POST",
      bodyData: nil,
      secret: secret
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GoodreadsSyncError.serverFailure(statusCode: 0, message: "Non-HTTP response")
    }

    if httpResponse.statusCode == 401 {
      throw GoodreadsSyncError.unauthorized
    }

    let decoded = try? JSONDecoder().decode(GoodreadsSyncResponse.self, from: data)
    guard (200...299).contains(httpResponse.statusCode) else {
      let message =
        decoded?.error
        ?? String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw GoodreadsSyncError.serverFailure(
        statusCode: httpResponse.statusCode,
        message: message
      )
    }

    return decoded
      ?? GoodreadsSyncResponse(
        ok: true,
        dryRun: nil,
        scanned: nil,
        created: nil,
        updated: nil,
        unchanged: nil,
        revalidated: nil,
        goodreadsItemsFetched: nil,
        createdCount: nil,
        updatedCount: nil,
        skippedCount: nil,
        durationMs: nil,
        error: nil
      )
  }

  // MARK: - Local-to-Contentful Book Mutations (SAG-28 / SAG-43)

  /// Pushes a single book upsert to `POST /api/books/sync` if configured.
  @discardableResult
  static func pushBookUpsertIfConfigured(_ payload: BookServerUpsertPayload) async
    -> BookServerSyncResponse?
  {
    await pushBooksSyncIfConfigured(upserts: [payload], deleteIds: [])
  }

  /// Pushes a batch of book upserts (chunked to respect server limits) to `POST /api/books/sync`.
  static func pushBookUpsertsIfConfigured(_ payloads: [BookServerUpsertPayload]) async {
    guard !payloads.isEmpty else { return }
    var startIndex = 0
    while startIndex < payloads.count {
      let endIndex = min(startIndex + maxBatchUpsertSize, payloads.count)
      let batch = Array(payloads[startIndex..<endIndex])
      _ = await pushBooksSyncIfConfigured(upserts: batch, deleteIds: [])
      startIndex = endIndex
    }
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
    guard !upserts.isEmpty || !deleteIds.isEmpty else { return nil }
    let secret = configuredSyncSecret
    guard !secret.isEmpty else {
      LoggerService.log(
        "Saga server secret not configured; skipping remote book mutation sync",
        level: .debug,
        surface: .sync
      )
      return nil
    }

    do {
      let response = try await syncBooks(
        urlString: configuredBooksMutationURLString,
        secret: secret,
        upserts: upserts,
        deleteIds: deleteIds
      )
      LoggerService.log(
        "Synced book mutations to dylangattey.com (upserted: \(response.upserted ?? upserts.count), deleted: \(response.deleted ?? deleteIds.count))",
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

  /// Executes a signed `POST /api/books/sync` request.
  static func syncBooks(
    urlString: String,
    secret: String,
    upserts: [BookServerUpsertPayload],
    deleteIds: [String]
  ) async throws -> BookServerSyncResponse {
    guard let url = resolvedEndpointURL(from: urlString, defaultPath: booksSyncPath) else {
      throw GoodreadsSyncError.invalidEndpointURL(rawValue: urlString)
    }

    let requestPayload = BookServerSyncRequest(
      upserts: upserts.isEmpty ? nil : upserts,
      deleteIds: deleteIds.isEmpty ? nil : deleteIds
    )
    let bodyData = try JSONEncoder().encode(requestPayload)
    let request = signedRequest(
      url: url,
      method: "POST",
      bodyData: bodyData,
      secret: secret
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GoodreadsSyncError.serverFailure(statusCode: 0, message: "Non-HTTP response")
    }

    if httpResponse.statusCode == 401 {
      throw GoodreadsSyncError.unauthorized
    }

    let decoded = try? JSONDecoder().decode(BookServerSyncResponse.self, from: data)
    guard (200...299).contains(httpResponse.statusCode) else {
      let message =
        decoded?.error
        ?? String(data: data, encoding: .utf8)
        ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw GoodreadsSyncError.serverFailure(
        statusCode: httpResponse.statusCode,
        message: message
      )
    }

    return decoded
      ?? BookServerSyncResponse(
        ok: true,
        upserted: upserts.count,
        deleted: deleteIds.count,
        revalidated: nil,
        entries: nil,
        error: nil
      )
  }

  // MARK: - URL Resolution Helpers

  private static func resolvedOrigin(from rawURLString: String) -> String? {
    let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = components.host,
      !host.isEmpty
    else {
      return nil
    }
    var origin = "\(scheme)://\(host)"
    if let port = components.port {
      origin += ":\(port)"
    }
    return origin
  }

  private static func resolvedEndpointURL(
    from rawURLString: String,
    defaultPath: String
  ) -> URL? {
    let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? (defaultServerOrigin + defaultPath) : trimmed
    guard var components = URLComponents(string: candidate),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = components.host,
      !host.isEmpty
    else {
      return nil
    }
    if components.path.isEmpty || components.path == "/" {
      components.path = defaultPath
    }
    return components.url
  }
}
