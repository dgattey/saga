//
//  CoverInput.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

@preconcurrency import Foundation
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

enum CoverInput: Equatable, Sendable {
  case remoteURL(URL)
  case imageData(Data)

  static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText]

  static func remoteURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
    let normalized = trimmed.hasPrefix("//") ? "https:" + trimmed : trimmed
    guard let url = URL(string: normalized),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host?.isEmpty == false
    else { return nil }
    return url
  }

  static func preferred(from candidates: [CoverInput]) -> CoverInput? {
    candidates.first {
      if case .remoteURL(let url) = $0 {
        return GoodreadsSyncService.sanitizedCoverImageURL(url.absoluteString) != nil
      }
      return false
    }
      ?? candidates.first {
        if case .imageData = $0 { return true }
        return false
      }
      ?? candidates.first
  }

  static func readFile(at url: URL) -> Data? {
    let isScoped = url.startAccessingSecurityScopedResource()
    defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
    return try? Data(contentsOf: url)
  }

  private static func from(url: URL) -> CoverInput? {
    url.isFileURL
      ? readFile(at: url).map(CoverInput.imageData)
      : remoteURL(from: url.absoluteString).map(CoverInput.remoteURL)
  }

  @MainActor
  static func load(from providers: [NSItemProvider]) async -> CoverInput? {
    var candidates: [CoverInput] = []
    for provider in providers {
      if provider.canLoadObject(ofClass: URL.self),
        let url: URL = await withCheckedContinuation({ cont in
          _ = provider.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }),
        let candidate = await Task.detached(priority: .userInitiated, operation: { from(url: url) })
          .value
      {
        candidates.append(candidate)
      }
      if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
        let data: Data = await withCheckedContinuation({ cont in
          _ = provider.loadDataRepresentation(for: .image) { data, _ in
            cont.resume(returning: data)
          }
        })
      {
        candidates.append(.imageData(data))
      }
      if provider.canLoadObject(ofClass: String.self),
        let text: String = await withCheckedContinuation({ cont in
          _ = provider.loadObject(ofClass: String.self) { text, _ in cont.resume(returning: text) }
        }),
        let remote = remoteURL(from: text)
      {
        candidates.append(.remoteURL(remote))
      }
    }
    return preferred(from: candidates)
  }

  static func fromClipboard() -> CoverInput? {
    var candidates: [CoverInput] = []
    #if canImport(AppKit)
      let pasteboard = NSPasteboard.general
      let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
      candidates.append(contentsOf: urls.compactMap(from(url:)))
      if let text = pasteboard.string(forType: .string), let remote = remoteURL(from: text) {
        candidates.append(.remoteURL(remote))
      }
      if let type = pasteboard.availableType(from: [.png, .tiff]),
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
