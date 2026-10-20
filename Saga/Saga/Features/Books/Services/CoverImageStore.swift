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

  var errorDescription: String? {
    switch self {
    case .notAnImage:
      return "That doesn't look like an image."
    case .writeFailed(let reason):
      return "Couldn't save the cover image: \(reason)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .notAnImage:
      return "Drop or paste a JPEG, PNG, or HEIC image, or an image URL."
    case .writeFailed:
      return "Check available disk space and try again."
    }
  }
}

/// Persists dropped or pasted cover images to Application Support so they render through the
/// regular `file://` image pipeline. These covers only live on this device: the books sync
/// endpoint accepts cover URLs from allowlisted hosts, not raw image uploads.
enum CoverImageStore {
  private static let passthroughTypes: [UTType] = [.jpeg, .png, .heic]

  static var defaultDirectory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return
      base
      .appending(path: Bundle.main.bundleIdentifier ?? "Saga", directoryHint: .isDirectory)
      .appending(path: "Covers", directoryHint: .isDirectory)
  }

  /// Validates `data` as an image and writes it to `directory`, returning the file URL. JPEG,
  /// PNG, and HEIC are stored as-is; anything else (like pasteboard TIFFs) is converted to PNG.
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
      (outputData, outputType) = (try pngData(from: source), .png)
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

  /// Whether `data` decodes as at least one image.
  static func isImage(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 0 && CGImageSourceGetType(source) != nil
  }

  /// Whether `urlString` points at a cover stored by this type (in any directory).
  static func isLocalCover(_ urlString: String?) -> Bool {
    guard let urlString, let url = URL(string: urlString) else { return false }
    return url.isFileURL
  }

  /// Deletes a cover previously written to `directory`. Ignores remote URLs and files elsewhere.
  static func remove(_ urlString: String?, in directory: URL = defaultDirectory) {
    guard let urlString, let url = URL(string: urlString), url.isFileURL,
      normalizedPath(url.deletingLastPathComponent()) == normalizedPath(directory)
    else {
      return
    }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      LoggerService.log(
        "Failed to remove replaced cover image",
        error: error,
        surface: .persistence
      )
    }
  }

  private static func normalizedPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  private static func pngData(from source: CGImageSource) throws -> Data {
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw CoverImageStoreError.notAnImage
    }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw CoverImageStoreError.writeFailed(reason: "PNG encoder unavailable")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CoverImageStoreError.writeFailed(reason: "PNG encoding failed")
    }
    return output as Data
  }
}
