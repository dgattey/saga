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
      return "That doesn't look like an image."
    case .writeFailed(let reason):
      return "Couldn't save the cover image: \(reason)"
    case .tooLargeToUpload(let bytes):
      return "The cover is still \(bytes / 1024) KB after compression, too large to sync."
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .notAnImage:
      return "Drop or paste a JPEG, PNG, or HEIC image, or an image URL."
    case .writeFailed:
      return "Check available disk space and try again."
    case .tooLargeToUpload:
      return "Try a smaller or simpler cover image. It still shows on this device."
    }
  }
}

/// A compressed cover ready to send as `coverImageBase64` + `coverImageContentType`.
struct CoverImageUpload: Equatable, Sendable {
  let data: Data
  let contentType: String

  var base64: String { data.base64EncodedString() }
}

/// Persists dropped or pasted cover images to Application Support so they render through the
/// regular `file://` image pipeline, and compresses them for upload to Contentful through
/// `/api/books/sync`.
enum CoverImageStore {
  private static let passthroughTypes: [UTType] = [.jpeg, .png, .heic]

  /// Keeps the base64 request body (~4/3 of this) under Vercel's 4.5 MB function payload limit.
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

  /// Downscales the cover at `fileURL` to at most 1600px on its long edge and re-encodes it as
  /// JPEG (flattening any transparency onto white), stepping down in size until it fits
  /// `maxUploadBytes`.
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
      let data = try jpegData(from: flattened(image))
      if data.count <= maxUploadBytes {
        return CoverImageUpload(data: data, contentType: "image/jpeg")
      }
      smallestSize = min(smallestSize, data.count)
    }
    throw CoverImageStoreError.tooLargeToUpload(bytes: smallestSize)
  }

  private static func flattened(_ image: CGImage) -> CGImage {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return image
    default:
      break
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
    else {
      return image
    }
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(bounds)
    context.draw(image, in: bounds)
    return context.makeImage() ?? image
  }

  private static func jpegData(from image: CGImage) throws -> Data {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw CoverImageStoreError.writeFailed(reason: "JPEG encoder unavailable")
    }
    let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: uploadJPEGQuality
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw CoverImageStoreError.writeFailed(reason: "JPEG encoding failed")
    }
    return output as Data
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
