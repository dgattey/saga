import Common
import Foundation

func findProjectPath(repoRoot: String) throws -> String {
  let path = URL(fileURLWithPath: repoRoot)
    .appendingPathComponent("Saga")
    .appendingPathComponent("Saga.xcodeproj")
    .path
  guard FileManager.default.fileExists(atPath: path) else {
    throw ScriptError("Xcode project not found at \(path)")
  }
  return path
}

func currentBranchName(repoRoot: String) -> String? {
  let output =
    (try? runCommand(
      "git", ["rev-parse", "--abbrev-ref", "HEAD"],
      cwd: URL(fileURLWithPath: repoRoot),
      allowFailure: true,
      emitOutput: false
    )) ?? ""
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty, trimmed != "HEAD" else { return nil }
  return trimmed
}

func currentShortCommit(repoRoot: String) -> String? {
  let output =
    (try? runCommand(
      "git", ["rev-parse", "--short", "HEAD"],
      cwd: URL(fileURLWithPath: repoRoot),
      allowFailure: true,
      emitOutput: false
    )) ?? ""
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

func sha256Hex(_ value: String) -> String? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["shasum", "-a", "256"]

  let stdin = Pipe()
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardInput = stdin
  process.standardOutput = stdout
  process.standardError = stderr

  do {
    try process.run()
  } catch {
    return nil
  }

  if let data = value.data(using: .utf8) {
    stdin.fileHandleForWriting.write(data)
  }
  stdin.fileHandleForWriting.closeFile()

  process.waitUntilExit()

  let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
  let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
  let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

  guard process.terminationStatus == 0 else {
    if !stderrText.isEmpty {
      FileHandle.standardError.write(stderrData)
    }
    return nil
  }

  let trimmed = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.split(separator: " ").first.map(String.init)
}

func buildCacheKey(repoRoot: String) -> String {
  if let branch = currentBranchName(repoRoot: repoRoot) {
    if let hash = sha256Hex(branch) {
      return hash
    }
  }
  if let shortCommit = currentShortCommit(repoRoot: repoRoot) {
    return shortCommit
  }
  return "unknown"
}

func buildApp(
  projectPath: String, arch: String, verbose: Bool, skipSigning: Bool
) throws {
  print("Building Saga (Debug)...")
  // Uses standard DerivedData location for hot reload compatibility
  var args = [
    "-project", projectPath,
    "-scheme", "Saga",
    "-configuration", "Debug",
    "-destination", "platform=macOS,arch=\(arch)",
    "build",
  ]
  if !verbose {
    args.insert("-quiet", at: 0)
  }
  // Skip code signing for CI environments without certificates
  if skipSigning {
    args.append(contentsOf: [
      "CODE_SIGN_IDENTITY=-",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO",
    ])
  }

  try runCommand("xcodebuild", args)
}
