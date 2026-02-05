//
//  ContentfulManagementService.swift
//  Saga
//
//  Handles writing data back to Contentful via the Content Management API (CMA).
//  This enables two-way sync: local CoreData changes are pushed to Contentful.
//

import CoreData
import Foundation

/// Errors that can occur during Contentful Management API operations
enum ContentfulManagementError: Error, LocalizedError {
  case missingManagementToken
  case invalidResponse(statusCode: Int, body: String?)
  case networkError(underlying: Error)
  case encodingError(underlying: Error)
  case assetUploadFailed(reason: String)
  case assetProcessingFailed(reason: String)
  case entryNotFound(id: String)
  case versionConflict(serverVersion: Int)

  var errorDescription: String? {
    switch self {
    case .missingManagementToken:
      return "Management API token not configured. Add ContentfulManagementToken to your config."
    case .invalidResponse(let statusCode, let body):
      return "Invalid response (status \(statusCode)): \(body ?? "no body")"
    case .networkError(let underlying):
      return "Network error: \(underlying.localizedDescription)"
    case .encodingError(let underlying):
      return "Encoding error: \(underlying.localizedDescription)"
    case .assetUploadFailed(let reason):
      return "Asset upload failed: \(reason)"
    case .assetProcessingFailed(let reason):
      return "Asset processing failed: \(reason)"
    case .entryNotFound(let id):
      return "Entry not found: \(id)"
    case .versionConflict(let serverVersion):
      return "Version conflict. Server version: \(serverVersion)"
    }
  }
}

/// Service for interacting with Contentful's Content Management API
/// Provides create, update, delete, and publish operations for entries and assets
actor ContentfulManagementService {
  private let spaceId: String
  private let environmentId: String
  private let managementToken: String
  private let session: URLSession

  private var baseURL: URL {
    URL(string: "https://api.contentful.com/spaces/\(spaceId)/environments/\(environmentId)")!
  }

  init(
    spaceId: String = BundleKey.spaceId.bundleValue,
    environmentId: String = "master",
    managementToken: String = BundleKey.managementToken.bundleValue
  ) throws {
    guard !managementToken.isEmpty else {
      throw ContentfulManagementError.missingManagementToken
    }
    self.spaceId = spaceId
    self.environmentId = environmentId
    self.managementToken = managementToken

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 120
    self.session = URLSession(configuration: config)
  }

  // MARK: - Entry Operations

  /// Creates a new entry in Contentful
  /// - Parameters:
  ///   - contentTypeId: The content type ID (e.g., "book")
  ///   - id: The entry ID (will be generated if nil)
  ///   - fields: The entry fields in Contentful format
  /// - Returns: The created entry's ID and version
  func createEntry(
    contentTypeId: String,
    id: String?,
    fields: [String: Any]
  ) async throws -> (id: String, version: Int) {
    let entryId = id ?? UUID().uuidString
    var request = makeRequest(path: "/entries/\(entryId)", method: "PUT")
    request.setValue(contentTypeId, forHTTPHeaderField: "X-Contentful-Content-Type")

    let body: [String: Any] = ["fields": fields]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    let version = httpResponse.value(forHTTPHeaderField: "X-Contentful-Version").flatMap(Int.init)
      ?? 1

    LoggerService.log(
      "Created entry \(entryId) (version \(version))", level: .debug, surface: .persistence)
    return (id: entryId, version: version)
  }

  /// Updates an existing entry in Contentful
  /// - Parameters:
  ///   - id: The entry ID
  ///   - version: The current version (for optimistic locking)
  ///   - fields: The updated fields
  /// - Returns: The new version number
  func updateEntry(
    id: String,
    version: Int,
    fields: [String: Any]
  ) async throws -> Int {
    var request = makeRequest(path: "/entries/\(id)", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let body: [String: Any] = ["fields": fields]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 409 {
      // Version conflict - need to fetch latest and merge
      let serverVersion = httpResponse.value(forHTTPHeaderField: "X-Contentful-Version")
        .flatMap(Int.init) ?? version
      throw ContentfulManagementError.versionConflict(serverVersion: serverVersion)
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    let newVersion = httpResponse.value(forHTTPHeaderField: "X-Contentful-Version")
      .flatMap(Int.init) ?? (version + 1)

    LoggerService.log(
      "Updated entry \(id) to version \(newVersion)", level: .debug, surface: .persistence)
    return newVersion
  }

  /// Deletes an entry from Contentful
  /// - Parameter id: The entry ID
  func deleteEntry(id: String) async throws {
    // First, unpublish if published
    do {
      try await unpublishEntry(id: id)
    } catch {
      // Ignore if not published
    }

    let request = makeRequest(path: "/entries/\(id)", method: "DELETE")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    LoggerService.log("Deleted entry \(id)", level: .debug, surface: .persistence)
  }

  /// Publishes an entry to make it available via the Content Delivery API
  /// - Parameters:
  ///   - id: The entry ID
  ///   - version: The version to publish
  func publishEntry(id: String, version: Int) async throws {
    var request = makeRequest(path: "/entries/\(id)/published", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    LoggerService.log("Published entry \(id)", level: .debug, surface: .persistence)
  }

  /// Unpublishes an entry
  /// - Parameter id: The entry ID
  func unpublishEntry(id: String) async throws {
    let request = makeRequest(path: "/entries/\(id)/published", method: "DELETE")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }
  }

  /// Fetches the current version of an entry
  /// - Parameter id: The entry ID
  /// - Returns: The current version and updatedAt timestamp
  func fetchEntryMetadata(id: String) async throws -> (version: Int, updatedAt: Date?) {
    let request = makeRequest(path: "/entries/\(id)", method: "GET")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 404 {
      throw ContentfulManagementError.entryNotFound(id: id)
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sys = json["sys"] as? [String: Any],
      let version = sys["version"] as? Int
    else {
      throw ContentfulManagementError.invalidResponse(statusCode: httpResponse.statusCode, body: nil)
    }

    var updatedAt: Date?
    if let updatedAtString = sys["updatedAt"] as? String {
      updatedAt = ISO8601DateFormatter().date(from: updatedAtString)
    }

    return (version: version, updatedAt: updatedAt)
  }

  /// Fetches the current version of an asset
  /// - Parameter id: The asset ID
  /// - Returns: The current version and updatedAt timestamp
  func fetchAssetMetadata(id: String) async throws -> (version: Int, updatedAt: Date?) {
    let request = makeRequest(path: "/assets/\(id)", method: "GET")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 404 {
      throw ContentfulManagementError.entryNotFound(id: id)
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sys = json["sys"] as? [String: Any],
      let version = sys["version"] as? Int
    else {
      throw ContentfulManagementError.invalidResponse(statusCode: httpResponse.statusCode, body: nil)
    }

    var updatedAt: Date?
    if let updatedAtString = sys["updatedAt"] as? String {
      updatedAt = ISO8601DateFormatter().date(from: updatedAtString)
    }

    return (version: version, updatedAt: updatedAt)
  }

  // MARK: - Asset Operations

  /// Uploads a new asset to Contentful
  /// This is a multi-step process:
  /// 1. Create the asset metadata
  /// 2. Upload the file
  /// 3. Process the asset
  /// 4. Publish the asset
  /// - Parameters:
  ///   - id: The asset ID (will be generated if nil)
  ///   - title: The asset title
  ///   - description: The asset description
  ///   - fileData: The raw file data
  ///   - fileName: The file name with extension
  ///   - contentType: The MIME type (e.g., "image/jpeg")
  /// - Returns: The created asset's ID, URL, and final version
  func uploadAsset(
    id: String?,
    title: String?,
    description: String?,
    fileData: Data,
    fileName: String,
    contentType: String
  ) async throws -> (id: String, url: String, version: Int) {
    let assetId = id ?? UUID().uuidString

    // Step 1: Upload the file to Contentful's upload endpoint
    let uploadId = try await uploadFile(data: fileData, fileName: fileName)

    // Step 2: Create the asset with a link to the upload
    let fields = buildAssetFields(
      title: title,
      description: description,
      fileName: fileName,
      contentType: contentType,
      uploadId: uploadId
    )

    var request = makeRequest(path: "/assets/\(assetId)", method: "PUT")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.assetUploadFailed(
        reason: "Failed to create asset: \(bodyString ?? "unknown")")
    }

    let version = httpResponse.value(forHTTPHeaderField: "X-Contentful-Version")
      .flatMap(Int.init) ?? 1

    // Step 3: Process the asset
    let processedVersion = try await processAsset(id: assetId, version: version)

    // Step 4: Publish the asset
    let finalVersion = try await publishAsset(id: assetId, version: processedVersion)

    // Fetch the final URL
    let assetURL = try await fetchAssetURL(id: assetId)

    LoggerService.log(
      "Uploaded and published asset \(assetId)", level: .debug, surface: .persistence)
    return (id: assetId, url: assetURL, version: finalVersion)
  }

  /// Updates an existing asset's metadata
  func updateAsset(
    id: String,
    version: Int,
    title: String?,
    description: String?
  ) async throws -> Int {
    var request = makeRequest(path: "/assets/\(id)", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let fields: [String: Any] = [
      "title": ["en-US": title ?? ""],
      "description": ["en-US": description ?? ""],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: bodyString)
    }

    return httpResponse.value(forHTTPHeaderField: "X-Contentful-Version").flatMap(Int.init)
      ?? (version + 1)
  }

  /// Deletes an asset from Contentful
  func deleteAsset(id: String) async throws {
    // First, unpublish if published
    do {
      try await unpublishAsset(id: id)
    } catch {
      // Ignore if not published
    }

    let request = makeRequest(path: "/assets/\(id)", method: "DELETE")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    LoggerService.log("Deleted asset \(id)", level: .debug, surface: .persistence)
  }

  // MARK: - Private Helpers

  private func makeRequest(path: String, method: String) -> URLRequest {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.setValue("Bearer \(managementToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.contentful.management.v1+json", forHTTPHeaderField: "Content-Type")
    return request
  }

  private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await session.data(for: request)
    } catch {
      throw ContentfulManagementError.networkError(underlying: error)
    }
  }

  private func uploadFile(data: Data, fileName: String) async throws -> String {
    let uploadURL = URL(string: "https://upload.contentful.com/spaces/\(spaceId)/uploads")!
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(managementToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.httpBody = data

    let (responseData, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let bodyString = String(data: responseData, encoding: .utf8)
      throw ContentfulManagementError.assetUploadFailed(
        reason: "File upload failed: \(bodyString ?? "unknown")")
    }

    guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let sys = json["sys"] as? [String: Any],
      let uploadId = sys["id"] as? String
    else {
      throw ContentfulManagementError.assetUploadFailed(reason: "Could not parse upload response")
    }

    return uploadId
  }

  private func buildAssetFields(
    title: String?,
    description: String?,
    fileName: String,
    contentType: String,
    uploadId: String
  ) -> [String: Any] {
    return [
      "title": ["en-US": title ?? fileName],
      "description": ["en-US": description ?? ""],
      "file": [
        "en-US": [
          "contentType": contentType,
          "fileName": fileName,
          "uploadFrom": [
            "sys": [
              "type": "Link",
              "linkType": "Upload",
              "id": uploadId,
            ]
          ],
        ]
      ],
    ]
  }

  private func processAsset(id: String, version: Int) async throws -> Int {
    var request = makeRequest(path: "/assets/\(id)/files/en-US/process", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let (_, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 204
    else {
      throw ContentfulManagementError.assetProcessingFailed(reason: "Process request failed")
    }

    // Wait for processing to complete (poll for up to 30 seconds)
    var processedVersion = version
    for _ in 0..<30 {
      try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      let checkRequest = makeRequest(path: "/assets/\(id)", method: "GET")
      let (data, checkResponse) = try await performRequest(checkRequest)

      guard let httpResponse = checkResponse as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode),
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let fields = json["fields"] as? [String: Any],
        let file = fields["file"] as? [String: Any],
        let enUS = file["en-US"] as? [String: Any]
      else {
        continue
      }

      // Check if file has URL (means processing is complete)
      if enUS["url"] != nil {
        if let sys = json["sys"] as? [String: Any], let ver = sys["version"] as? Int {
          processedVersion = ver
        }
        return processedVersion
      }
    }

    throw ContentfulManagementError.assetProcessingFailed(reason: "Timed out waiting for processing")
  }

  private func publishAsset(id: String, version: Int) async throws -> Int {
    var request = makeRequest(path: "/assets/\(id)/published", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.assetUploadFailed(
        reason: "Publish failed: \(bodyString ?? "unknown")")
    }

    return httpResponse.value(forHTTPHeaderField: "X-Contentful-Version").flatMap(Int.init)
      ?? (version + 1)
  }

  private func unpublishAsset(id: String) async throws {
    let request = makeRequest(path: "/assets/\(id)/published", method: "DELETE")
    let (_, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404
    else {
      // Ignore unpublish failures
      return
    }
  }

  private func fetchAssetURL(id: String) async throws -> String {
    let request = makeRequest(path: "/assets/\(id)", method: "GET")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let fields = json["fields"] as? [String: Any],
      let file = fields["file"] as? [String: Any],
      let enUS = file["en-US"] as? [String: Any],
      let url = enUS["url"] as? String
    else {
      throw ContentfulManagementError.assetUploadFailed(reason: "Could not fetch asset URL")
    }

    // Contentful returns URLs without protocol
    return url.hasPrefix("//") ? "https:\(url)" : url
  }
}
