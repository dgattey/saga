//
//  CoverImageStore.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverImageStoreError: LocalizedError, Equatable {
  case notAnImage
  case writeFailed(reason: String)
  case tooLargeToUpload(bytes: Int)

  var errorDescription: String? {
    switch self {
    case .notAnImage:
      "That doesn't look like an image."
    case .writeFailed(let reason):
      "Couldn't save the cover image: \(reason)"
    case .tooLargeToUpload(let bytes):
      "The cover is still \(bytes / 1024) KB after compression, too large to sync."
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .notAnImage:
      "Drop or paste a JPEG, PNG, or HEIC image, or an image URL."
    case .writeFailed:
      "Check available disk space and try again."
    case .tooLargeToUpload:
      "Try a smaller or simpler cover image. It still shows on this device."
    }
  }
}

struct CoverImageUpload: Equatable, Sendable {
  let data: Data
  let contentType: String

  var base64: String { data.base64EncodedString() }
}

enum CoverImageStore {
  private static let passthroughTypes: [UTType] = [.jpeg, .png, .heic]
  static let maxUploadBytes = 3 * 1024 * 1024
  private static let uploadPixelSizes = [1600, 1200, 800]
  private static let uploadJPEGQuality = 0.82

  static var defaultDirectory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return
      base
      .appending(path: Bundle.main.bundleIdentifier ?? "Saga", directoryHint: .isDirectory)
      .appending(path: "Covers", directoryHint: .isDirectory)
  }

  static func save(_ data: Data, in directory: URL = defaultDirectory) throws -> URL {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let typeIdentifier = CGImageSourceGetType(source) as String?,
      let sourceType = UTType(typeIdentifier)
    else {
      throw CoverImageStoreError.notAnImage
    }

    let (outputData, outputType): (Data, UTType)
    if passthroughTypes.contains(where: { sourceType.conforms(to: $0) }) {
      (outputData, outputType) = (data, sourceType)
    } else {
      guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CoverImageStoreError.notAnImage
      }
      (outputData, outputType) = (try encode(image, as: .png), .png)
    }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let fileURL = directory.appending(
        path: "\(UUID().uuidString).\(outputType.preferredFilenameExtension ?? "png")"
      )
      try outputData.write(to: fileURL, options: .atomic)
      return fileURL
    } catch {
      throw CoverImageStoreError.writeFailed(reason: error.localizedDescription)
    }
  }

  static func isImage(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
  }

  static func isLocalCover(_ urlString: String?) -> Bool {
    guard let urlString, let url = URL(string: urlString) else { return false }
    return url.isFileURL
  }

  static func remove(_ urlString: String?, in directory: URL = defaultDirectory) {
    guard let urlString, let url = URL(string: urlString), url.isFileURL,
      url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      LoggerService.log(
        "Failed to remove replaced cover image", error: error, surface: .persistence)
    }
  }

  static func uploadData(forCoverAt fileURL: URL) throws -> CoverImageUpload {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else {
      throw CoverImageStoreError.notAnImage
    }
    var smallestSize = Int.max
    for pixelSize in uploadPixelSizes {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: pixelSize,
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else {
        throw CoverImageStoreError.notAnImage
      }
      let data = try encode(flattened(image), as: .jpeg, quality: uploadJPEGQuality)
      if data.count <= maxUploadBytes {
        return CoverImageUpload(data: data, contentType: "image/jpeg")
      }
      smallestSize = min(smallestSize, data.count)
    }
    throw CoverImageStoreError.tooLargeToUpload(bytes: smallestSize)
  }

  private static func flattened(_ image: CGImage) -> CGImage {
    if [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) {
      return image
    }
    guard
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { return image }
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(bounds)
    context.draw(image, in: bounds)
    return context.makeImage() ?? image
  }

  private static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws
    -> Data
  {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, type.identifier as CFString, 1, nil
      )
    else {
      throw CoverImageStoreError.writeFailed(reason: "\(type.identifier) encoder unavailable")
    }
    let properties = quality.map {
      [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
    }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
      throw CoverImageStoreError.writeFailed(reason: "\(type.identifier) encoding failed")
    }
    return output as Data
  }
}

enum CoverImageResolver {
  private static let cache = CoverImageURLCache()

  static func bestCoverURL(isbn: String?, title: String, author: String) async -> String? {
    guard !PersistenceService.isRunningUnitTests else { return nil }
    let normalizedTitle = title.cleanedWhitespace
    let normalizedAuthor = author.cleanedWhitespace
    guard let isbn = isbn?.cleanedWhitespace, !isbn.isEmpty else {
      guard !normalizedTitle.isEmpty else { return nil }
      return try? await OpenLibraryAPIService.coverImageURL(
        forTitle: normalizedTitle, author: normalizedAuthor
      )
    }
    return await cache.value(forISBN: isbn) {
      do {
        let openLibrary = try await OpenLibraryAPIService.bestCoverCandidate(
          forISBN: isbn, title: normalizedTitle, author: normalizedAuthor
        )
        let bookcover =
          (openLibrary?.bytes ?? 0) < 80_000
          ? try await BookcoverAPIService.coverImageCandidate(forISBN: isbn) : nil
        return preferredCandidate(openLibrary: openLibrary, bookcover: bookcover)?.url
      } catch {
        LoggerService.log(
          "Cover lookup failed for ISBN \(isbn)", error: error, surface: .network)
        return nil
      }
    }
  }

  static func preferredCandidate(
    openLibrary: CoverImageCandidate?,
    bookcover: CoverImageCandidate?
  ) -> CoverImageCandidate? {
    guard let openLibrary else { return bookcover }
    guard let bookcover else { return openLibrary }
    if bookcover.bytes >= 30_000, Double(bookcover.bytes) >= Double(openLibrary.bytes) * 0.85 {
      return bookcover
    }
    return openLibrary.bytes >= bookcover.bytes ? openLibrary : bookcover
  }
}

private actor CoverImageURLCache {
  private var values: [String: String] = [:]
  private var tasks: [String: Task<String?, Never>] = [:]

  func value(forISBN isbn: String, fetch: @escaping @Sendable () async -> String?) async -> String?
  {
    if let cached = values[isbn] { return cached }
    if let existingTask = tasks[isbn] { return await existingTask.value }
    let task = Task { await fetch() }
    tasks[isbn] = task
    let value = await task.value
    tasks[isbn] = nil
    values[isbn] = value
    return value
  }
}
