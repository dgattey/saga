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
  case decodingError(underlying: Error)
  case assetUploadFailed(reason: String)
  case assetProcessingFailed(reason: String)
  case resourceNotFound(type: ContentfulResourceType, id: String)
  case versionConflict(serverVersion: Int)
  case rateLimitExceeded(retryAfter: TimeInterval)

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
    case .decodingError(let underlying):
      return "Decoding error: \(underlying.localizedDescription)"
    case .assetUploadFailed(let reason):
      return "Asset upload failed: \(reason)"
    case .assetProcessingFailed(let reason):
      return "Asset processing failed: \(reason)"
    case .resourceNotFound(let type, let id):
      return "\(type.rawValue.dropLast()) not found: \(id)"
    case .versionConflict(let serverVersion):
      return "Version conflict. Server version: \(serverVersion)"
    case .rateLimitExceeded(let retryAfter):
      return "Rate limit exceeded. Retry after \(retryAfter)s"
    }
  }
}

/// Service for interacting with Contentful's Content Management API.
/// Provides generic create, update, delete, and publish operations for entries and assets.
actor ContentfulManagementService {
  private let spaceId: String
  private let environmentId: String
  private let managementToken: String
  private let session: URLSession

  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private var baseURL: URL {
    URL(string: "https://api.contentful.com/spaces/\(spaceId)/environments/\(environmentId)")!
  }

  private var uploadURL: URL {
    URL(string: "https://upload.contentful.com/spaces/\(spaceId)/uploads")!
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

    // Configure encoder/decoder
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()

    // Custom date decoding to handle Contentful's fractional-second timestamps
    // (e.g., "2024-01-15T10:30:00.123Z"). The standard .iso8601 strategy doesn't
    // support fractional seconds.
    self.decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      // Try with fractional seconds first (Contentful CMA format)
      let formatterWithFractional = ISO8601DateFormatter()
      formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatterWithFractional.date(from: dateString) {
        return date
      }

      // Fallback to standard ISO8601 without fractional seconds
      let formatter = ISO8601DateFormatter()
      if let date = formatter.date(from: dateString) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Cannot decode date: \(dateString)"
      )
    }
  }

  // MARK: - Generic Resource Operations

  /// Fetches metadata (sys) for any resource type
  /// - Parameters:
  ///   - type: The resource type (entry or asset)
  ///   - id: The resource ID
  /// - Returns: The sys metadata including version and updatedAt
  func fetchMetadata(_ type: ContentfulResourceType, id: String) async throws -> ContentfulSys {
    let request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "GET")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 404 {
      throw ContentfulManagementError.resourceNotFound(type: type, id: id)
    }

    try validateResponse(httpResponse, data: data)
    return try decodeResource(from: data).sys
  }

  /// Creates a new resource
  /// - Parameters:
  ///   - type: The resource type (entry or asset)
  ///   - id: The resource ID
  ///   - fields: The fields payload (must be Encodable)
  ///   - contentTypeId: Required for entries, nil for assets
  /// - Returns: The sys metadata of the created resource
  func create<Fields: Encodable>(
    _ type: ContentfulResourceType,
    id: String,
    fields: Fields,
    contentTypeId: String? = nil
  ) async throws -> ContentfulSys {
    var request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "PUT")

    // Entries require the content type header
    if let contentTypeId = contentTypeId {
      request.setValue(contentTypeId, forHTTPHeaderField: "X-Contentful-Content-Type")
    }

    let envelope = EntryEnvelope(fields)
    request.httpBody = try encodeBody(envelope)

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    try validateResponse(httpResponse, data: data)

    let sys = try decodeResource(from: data).sys
    LoggerService.log(
      "Created \(type.rawValue.dropLast()) \(id) (version \(sys.version))",
      level: .debug,
      surface: .persistence
    )
    return sys
  }

  /// Updates an existing resource
  /// - Parameters:
  ///   - type: The resource type (entry or asset)
  ///   - id: The resource ID
  ///   - version: The current version for optimistic locking
  ///   - fields: The updated fields payload
  /// - Returns: The sys metadata with the new version
  func update<Fields: Encodable>(
    _ type: ContentfulResourceType,
    id: String,
    version: Int,
    fields: Fields
  ) async throws -> ContentfulSys {
    var request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let envelope = EntryEnvelope(fields)
    request.httpBody = try encodeBody(envelope)

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 409 {
      // Version conflict - extract server version from body if possible
      if let resource = try? decodeResource(from: data) {
        throw ContentfulManagementError.versionConflict(serverVersion: resource.sys.version)
      }
      throw ContentfulManagementError.versionConflict(serverVersion: version)
    }

    try validateResponse(httpResponse, data: data)

    let sys = try decodeResource(from: data).sys
    LoggerService.log(
      "Updated \(type.rawValue.dropLast()) \(id) to version \(sys.version)",
      level: .debug,
      surface: .persistence
    )
    return sys
  }

  /// Creates a new resource with pre-encoded fields data (for existential type erasure)
  func createRaw(
    _ type: ContentfulResourceType,
    id: String,
    fieldsData: Data,
    contentTypeId: String? = nil
  ) async throws -> ContentfulSys {
    var request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "PUT")

    if let contentTypeId = contentTypeId {
      request.setValue(contentTypeId, forHTTPHeaderField: "X-Contentful-Content-Type")
    }

    request.httpBody = fieldsData

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    try validateResponse(httpResponse, data: data)

    let sys = try decodeResource(from: data).sys
    LoggerService.log(
      "Created \(type.rawValue.dropLast()) \(id) (version \(sys.version))",
      level: .debug,
      surface: .persistence
    )
    return sys
  }

  /// Updates an existing resource with pre-encoded fields data (for existential type erasure)
  func updateRaw(
    _ type: ContentfulResourceType,
    id: String,
    version: Int,
    fieldsData: Data
  ) async throws -> ContentfulSys {
    var request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    request.httpBody = fieldsData

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    if httpResponse.statusCode == 409 {
      if let resource = try? decodeResource(from: data) {
        throw ContentfulManagementError.versionConflict(serverVersion: resource.sys.version)
      }
      throw ContentfulManagementError.versionConflict(serverVersion: version)
    }

    try validateResponse(httpResponse, data: data)

    let sys = try decodeResource(from: data).sys
    LoggerService.log(
      "Updated \(type.rawValue.dropLast()) \(id) to version \(sys.version)",
      level: .debug,
      surface: .persistence
    )
    return sys
  }

  /// Publishes a resource to make it available via CDA
  /// - Parameters:
  ///   - type: The resource type
  ///   - id: The resource ID
  ///   - version: The version to publish
  /// - Returns: The sys metadata after publishing (version will be incremented)
  func publish(_ type: ContentfulResourceType, id: String, version: Int) async throws
    -> ContentfulSys
  {
    var request = makeRequest(path: "/\(type.rawValue)/\(id)/published", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    try validateResponse(httpResponse, data: data)

    let sys = try decodeResource(from: data).sys
    LoggerService.log(
      "Published \(type.rawValue.dropLast()) \(id)", level: .debug, surface: .persistence)
    return sys
  }

  /// Unpublishes a resource
  func unpublish(_ type: ContentfulResourceType, id: String) async throws {
    let request = makeRequest(path: "/\(type.rawValue)/\(id)/published", method: "DELETE")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    // 404 is fine - means it wasn't published
    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }
  }

  /// Deletes a resource (unpublishes first if needed)
  func delete(_ type: ContentfulResourceType, id: String) async throws {
    // First, unpublish if published
    try? await unpublish(type, id: id)

    let request = makeRequest(path: "/\(type.rawValue)/\(id)", method: "DELETE")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ContentfulManagementError.invalidResponse(statusCode: 0, body: nil)
    }

    // 404 is fine - means it was already deleted
    guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: httpResponse.statusCode, body: bodyString)
    }

    LoggerService.log(
      "Deleted \(type.rawValue.dropLast()) \(id)", level: .debug, surface: .persistence)
  }

  // MARK: - Asset-Specific Operations

  /// Uploads a new asset to Contentful (multi-step process)
  /// 1. Upload the file to get an upload ID
  /// 2. Create the asset with a link to the upload
  /// 3. Process the asset
  /// 4. Publish the asset
  /// - Returns: The sys metadata and the final URL
  func uploadAsset(
    id: String,
    title: String?,
    description: String?,
    fileData: Data,
    fileName: String,
    contentType: String
  ) async throws -> (sys: ContentfulSys, url: String) {
    // Step 1: Upload the file
    let uploadId = try await uploadFile(data: fileData, fileName: fileName)

    // Step 2: Create the asset with upload link
    let fields = AssetFieldsPayload.withUpload(
      title: title,
      description: description,
      fileName: fileName,
      contentType: contentType,
      uploadId: uploadId
    )
    let createSys = try await create(.asset, id: id, fields: fields)

    // Step 3: Process the asset
    let processedSys = try await processAsset(id: id, version: createSys.version)

    // Step 4: Publish the asset
    let publishedSys = try await publish(.asset, id: id, version: processedSys.version)

    // Step 5: Fetch the final URL
    let url = try await fetchAssetURL(id: id)

    LoggerService.log(
      "Uploaded and published asset \(id)", level: .debug, surface: .persistence)
    return (sys: publishedSys, url: url)
  }

  // MARK: - Private Helpers

  private func makeRequest(path: String, method: String) -> URLRequest {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.setValue("Bearer \(managementToken)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "application/vnd.contentful.management.v1+json", forHTTPHeaderField: "Content-Type")
    return request
  }

  /// Performs a request with automatic retry for transient errors and rate limits
  /// - Retries up to 3 times with exponential backoff (1s, 2s, 4s) for 5xx errors and network errors
  /// - Honors X-Contentful-RateLimit-Reset header for 429 responses
  private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
    let maxRetries = 3
    var lastError: Error?

    for attempt in 0..<maxRetries {
      do {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
          return (data, response)
        }

        // Handle rate limiting (429)
        if httpResponse.statusCode == 429 {
          let retryAfter = parseRetryAfter(from: httpResponse)
          if attempt < maxRetries - 1 {
            LoggerService.log(
              "Rate limited, waiting \(retryAfter)s before retry (attempt \(attempt + 1)/\(maxRetries))",
              level: .notice,
              surface: .persistence
            )
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            continue
          } else {
            throw ContentfulManagementError.rateLimitExceeded(retryAfter: retryAfter)
          }
        }

        // Handle server errors (5xx) with retry
        if (500...599).contains(httpResponse.statusCode) {
          if attempt < maxRetries - 1 {
            let delay = pow(2.0, Double(attempt))  // 1s, 2s, 4s
            LoggerService.log(
              "Server error \(httpResponse.statusCode), retrying in \(delay)s (attempt \(attempt + 1)/\(maxRetries))",
              level: .notice,
              surface: .persistence
            )
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            continue
          }
        }

        return (data, response)

      } catch let error as ContentfulManagementError {
        throw error  // Don't retry our own errors
      } catch let error as URLError where isTransientError(error) {
        lastError = error
        if attempt < maxRetries - 1 {
          let delay = pow(2.0, Double(attempt))  // 1s, 2s, 4s
          LoggerService.log(
            "Network error (\(error.code.rawValue)), retrying in \(delay)s (attempt \(attempt + 1)/\(maxRetries))",
            level: .notice,
            surface: .persistence
          )
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          continue
        }
      } catch {
        throw ContentfulManagementError.networkError(underlying: error)
      }
    }

    throw ContentfulManagementError.networkError(underlying: lastError ?? URLError(.unknown))
  }

  /// Parses the retry-after header from a rate-limited response
  private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval {
    // Contentful uses X-Contentful-RateLimit-Reset header (seconds until reset)
    if let resetHeader = response.value(forHTTPHeaderField: "X-Contentful-RateLimit-Reset"),
      let resetSeconds = Double(resetHeader)
    {
      return resetSeconds
    }
    // Fallback to standard Retry-After header
    if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
      let seconds = Double(retryAfter)
    {
      return seconds
    }
    // Default to 1 second if no header present
    return 1.0
  }

  /// Determines if a URLError is transient and worth retrying
  private func isTransientError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut, .cannotConnectToHost, .networkConnectionLost,
      .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
      .callIsActive, .dataNotAllowed:
      return true
    default:
      return false
    }
  }

  private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
    guard (200...299).contains(response.statusCode) else {
      let bodyString = String(data: data, encoding: .utf8)
      throw ContentfulManagementError.invalidResponse(
        statusCode: response.statusCode, body: bodyString)
    }
  }

  private func encodeBody<T: Encodable>(_ value: T) throws -> Data {
    do {
      return try encoder.encode(value)
    } catch {
      throw ContentfulManagementError.encodingError(underlying: error)
    }
  }

  private func decodeResource(from data: Data) throws -> ContentfulResource {
    do {
      return try decoder.decode(ContentfulResource.self, from: data)
    } catch {
      throw ContentfulManagementError.decodingError(underlying: error)
    }
  }

  private func uploadFile(data: Data, fileName: String) async throws -> String {
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

    do {
      let uploadResponse = try decoder.decode(ContentfulUploadResponse.self, from: responseData)
      return uploadResponse.sys.id
    } catch {
      throw ContentfulManagementError.assetUploadFailed(reason: "Could not parse upload response")
    }
  }

  private func processAsset(id: String, version: Int) async throws -> ContentfulSys {
    var request = makeRequest(path: "/assets/\(id)/files/en-US/process", method: "PUT")
    request.setValue(String(version), forHTTPHeaderField: "X-Contentful-Version")

    let (_, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 204
    else {
      throw ContentfulManagementError.assetProcessingFailed(reason: "Process request failed")
    }

    // Wait for processing to complete with exponential backoff
    var delay: UInt64 = 1_000_000_000  // Start at 1 second
    let maxDelay: UInt64 = 8_000_000_000  // Cap at 8 seconds
    let maxAttempts = 15

    for attempt in 0..<maxAttempts {
      try await Task.sleep(nanoseconds: delay)

      let checkRequest = makeRequest(path: "/assets/\(id)", method: "GET")
      let (data, checkResponse) = try await performRequest(checkRequest)

      guard let httpResponse = checkResponse as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        continue
      }

      do {
        let assetResponse = try decoder.decode(AssetResponse.self, from: data)

        // Check if file has URL (means processing is complete)
        if assetResponse.fields?.file?.enUS.url != nil {
          return assetResponse.sys
        }
      } catch {
        // Decoding failed, continue waiting
      }

      // Exponential backoff
      if attempt < 3 {
        delay = min(delay * 2, maxDelay)
      }
    }

    throw ContentfulManagementError.assetProcessingFailed(
      reason: "Timed out waiting for processing")
  }

  private func fetchAssetURL(id: String) async throws -> String {
    let request = makeRequest(path: "/assets/\(id)", method: "GET")
    let (data, response) = try await performRequest(request)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw ContentfulManagementError.assetUploadFailed(reason: "Could not fetch asset")
    }

    do {
      let assetResponse = try decoder.decode(AssetResponse.self, from: data)
      guard let url = assetResponse.fields?.file?.enUS.url else {
        throw ContentfulManagementError.assetUploadFailed(reason: "Asset has no URL")
      }
      // Contentful returns URLs without protocol
      return url.hasPrefix("//") ? "https:\(url)" : url
    } catch let error as ContentfulManagementError {
      throw error
    } catch {
      throw ContentfulManagementError.assetUploadFailed(reason: "Could not parse asset response")
    }
  }
}
