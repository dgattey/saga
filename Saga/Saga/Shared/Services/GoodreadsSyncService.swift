//
//  GoodreadsSyncService.swift
//  Saga
//
//  Created by Dylan Gattey on 10/14/26.
//

import Foundation

/// Response returned by `/api/cron/goodreads-sync`.
struct GoodreadsSyncResponse: Decodable, Sendable {
  let ok: Bool
  let dryRun: Bool?
  let goodreadsItemsFetched: Int?
  let createdCount: Int?
  let updatedCount: Int?
  let skippedCount: Int?
  let durationMs: Int?
  let error: String?
}

/// Errors encountered when triggering the remote Goodreads → Contentful sync endpoint.
enum GoodreadsSyncError: LocalizedError {
  case invalidEndpointURL(rawValue: String)
  case unauthorized
  case serverFailure(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpointURL(let rawValue):
      return "Invalid Goodreads sync URL: \(rawValue)"
    case .unauthorized:
      return "Goodreads sync endpoint rejected the Bearer secret (HTTP 401)."
    case .serverFailure(let statusCode, let message):
      return "Goodreads sync endpoint returned HTTP \(statusCode): \(message)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .invalidEndpointURL:
      return
        "Verify GOODREADS_SYNC_URL in Config.xcconfig or Settings points to /api/cron/goodreads-sync."
    case .unauthorized:
      return "Verify GOODREADS_SYNC_SECRET matches CRON_SECRET on your Vercel deployment."
    case .serverFailure:
      return "Check Vercel function logs and Contentful Management API credentials."
    }
  }
}

/// Triggers the Vercel `/api/cron/goodreads-sync` webhook prior to pulling from Contentful CDA.
enum GoodreadsSyncService {
  static let syncURLStorageKey = "goodreadsSyncURLOverride"
  static let syncSecretStorageKey = "goodreadsSyncSecretOverride"

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 25
    configuration.timeoutIntervalForResource = 45
    return URLSession(configuration: configuration)
  }()

  /// Returns the active Goodreads sync endpoint URL (UserDefaults override if non-empty, otherwise `BundleKey.goodreadsSyncURL`).
  static var configuredSyncURLString: String {
    let override =
      UserDefaults.standard.string(forKey: syncURLStorageKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty {
      return override
    }
    return BundleKey.goodreadsSyncURL.bundleValue
  }

  /// Returns the active Goodreads sync Bearer secret (UserDefaults override if non-empty, otherwise `BundleKey.goodreadsSyncSecret`).
  static var configuredSyncSecret: String {
    let override =
      UserDefaults.standard.string(forKey: syncSecretStorageKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty {
      return override
    }
    return BundleKey.goodreadsSyncSecret.bundleValue
  }

  static var isConfigured: Bool {
    !configuredSyncURLString.isEmpty
  }

  /// Triggers `/api/cron/goodreads-sync` if configured.
  /// Logs and swallows errors so Contentful CDA sync always proceeds gracefully.
  @discardableResult
  static func triggerIfConfigured() async -> GoodreadsSyncResponse? {
    let rawURL = configuredSyncURLString
    guard !rawURL.isEmpty else {
      LoggerService.log(
        "Goodreads sync webhook not configured; skipping pre-sync trigger",
        level: .debug,
        surface: .sync
      )
      return nil
    }

    do {
      let response = try await trigger(urlString: rawURL, secret: configuredSyncSecret)
      let created = response.createdCount ?? 0
      let updated = response.updatedCount ?? 0
      let skipped = response.skippedCount ?? 0
      LoggerService.log(
        "Goodreads sync completed (created: \(created), updated: \(updated), skipped: \(skipped))",
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

  /// Executes the HTTP POST request to the Goodreads sync endpoint.
  static func trigger(urlString: String, secret: String) async throws -> GoodreadsSyncResponse {
    guard let url = URL(string: urlString),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http"
    else {
      throw GoodreadsSyncError.invalidEndpointURL(rawValue: urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if !secret.isEmpty {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

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
        goodreadsItemsFetched: nil,
        createdCount: nil,
        updatedCount: nil,
        skippedCount: nil,
        durationMs: nil,
        error: nil
      )
  }
}
