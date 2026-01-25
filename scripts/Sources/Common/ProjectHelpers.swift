import Foundation

// MARK: - Project helpers

/// Locates the Saga Xcode project at the repo root.
public func findProjectPath(repoRoot: String) throws -> String {
  let path = URL(fileURLWithPath: repoRoot)
    .appendingPathComponent("Saga")
    .appendingPathComponent("Saga.xcodeproj")
    .path
  guard FileManager.default.fileExists(atPath: path) else {
    throw ScriptError("Xcode project not found at \(path)")
  }
  return path
}
