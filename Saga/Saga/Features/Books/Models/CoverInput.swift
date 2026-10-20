//
//  CoverInput.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import Foundation
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// A cover image the user dropped or pasted: either a remote image URL or raw image bytes.
enum CoverInput: Equatable {
  case remoteURL(URL)
  case imageData(Data)

  /// Drop and paste types the cover picker accepts.
  static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText]

  /// Parses user-entered text as an `http(s)` URL, upgrading protocol-relative `//` URLs.
  static func remoteURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
    let normalized = trimmed.hasPrefix("//") ? "https:" + trimmed : trimmed
    guard let url = URL(string: normalized),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host?.isEmpty == false
    else {
      return nil
    }
    return url
  }

  /// Picks the most useful input when a drop or paste offers several representations: a URL
  /// that can sync to Contentful wins, then image bytes, then any other remote URL.
  static func preferred(from candidates: [CoverInput]) -> CoverInput? {
    let syncableURL = candidates.first { candidate in
      guard case .remoteURL(let url) = candidate else { return false }
      return GoodreadsSyncService.sanitizedCoverImageURL(url.absoluteString) != nil
    }
    let imageData = candidates.first { candidate in
      if case .imageData = candidate { return true }
      return false
    }
    return syncableURL ?? imageData ?? candidates.first
  }

  // MARK: - Drag and drop

  /// Loads every supported representation from dropped item providers and picks the best one.
  static func load(from providers: [NSItemProvider]) async -> CoverInput? {
    var candidates: [CoverInput] = []
    for provider in providers {
      candidates.append(contentsOf: await loadCandidates(from: provider))
    }
    return preferred(from: candidates)
  }

  private static func loadCandidates(from provider: NSItemProvider) async -> [CoverInput] {
    var candidates: [CoverInput] = []
    if provider.canLoadObject(ofClass: URL.self), let url = await loadURL(from: provider) {
      if url.isFileURL {
        if let data = readFile(at: url) {
          candidates.append(.imageData(data))
        }
      } else if let remote = remoteURL(from: url.absoluteString) {
        candidates.append(.remoteURL(remote))
      }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
      let data = await loadImageData(from: provider)
    {
      candidates.append(.imageData(data))
    }
    if provider.canLoadObject(ofClass: String.self),
      let text = await loadString(from: provider),
      let remote = remoteURL(from: text)
    {
      candidates.append(.remoteURL(remote))
    }
    return candidates
  }

  private static func loadURL(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        continuation.resume(returning: url)
      }
    }
  }

  private static func loadString(from provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
      _ = provider.loadObject(ofClass: String.self) { text, _ in
        continuation.resume(returning: text)
      }
    }
  }

  private static func loadImageData(from provider: NSItemProvider) async -> Data? {
    await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(for: .image) { data, _ in
        continuation.resume(returning: data)
      }
    }
  }

  /// Reads a user-selected or dropped file, honoring security-scoped access when sandboxed.
  static func readFile(at url: URL) -> Data? {
    let isScoped = url.startAccessingSecurityScopedResource()
    defer {
      if isScoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try? Data(contentsOf: url)
  }

  // MARK: - Clipboard

  /// Reads the system clipboard for an image, image file, or image URL.
  static func fromClipboard() -> CoverInput? {
    var candidates: [CoverInput] = []
    #if canImport(AppKit)
      let pasteboard = NSPasteboard.general
      let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
      for url in urls {
        if url.isFileURL {
          if let data = readFile(at: url) {
            candidates.append(.imageData(data))
          }
        } else if let remote = remoteURL(from: url.absoluteString) {
          candidates.append(.remoteURL(remote))
        }
      }
      if let text = pasteboard.string(forType: .string), let remote = remoteURL(from: text) {
        candidates.append(.remoteURL(remote))
      }
      let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
      if let type = pasteboard.availableType(from: imageTypes),
        let data = pasteboard.data(forType: type)
      {
        candidates.append(.imageData(data))
      }
    #elseif canImport(UIKit)
      let pasteboard = UIPasteboard.general
      if let url = pasteboard.url, let remote = remoteURL(from: url.absoluteString) {
        candidates.append(.remoteURL(remote))
      }
      if let text = pasteboard.string, let remote = remoteURL(from: text) {
        candidates.append(.remoteURL(remote))
      }
      if let data = pasteboard.image?.pngData() {
        candidates.append(.imageData(data))
      }
    #endif
    return preferred(from: candidates)
  }
}
