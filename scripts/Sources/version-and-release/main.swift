// DESCRIPTION: Manage version tags and Github releases

import Common
import Foundation

// MARK: - Constants

enum Constants {
  static let marketingVersionKey = "MARKETING_VERSION"
  static let buildVersionKey = "CURRENT_PROJECT_VERSION"
  static let metadataStart = "<!-- release-metadata-start -->"
  static let metadataEnd = "<!-- release-metadata-end -->"
  static let whatChangedHeading = "What changed?"
  static let releaseTypeHeading = "Release info"
  static let releaseTypeMajor = "Major"
  static let releaseTypeMinor = "Minor"
}

// MARK: - CLI

enum Command: String, CLISubcommandType, CaseIterable {
  case read
  case bump
  case prInfo = "pr-info"
  case extractNotes = "extract-notes"
  case updateMetadata = "update-metadata"

  var description: String {
    switch self {
    case .read: "Read version/build from project file"
    case .bump: "Compute and write next version"
    case .prInfo: "Parse release type from PR event"
    case .extractNotes: "Extract release notes from PR body"
    case .updateMetadata: "Update PR body with version block"
    }
  }
}

let cli = SimpleCLI(
  filePath: #filePath,
  subcommands: Command.allCases.map { ($0.rawValue, $0.description) },
  examples: [
    "run version-and-release read --path project.pbxproj",
    "run version-and-release bump --path project.pbxproj --base-version 1.0.0 \\",
    "  --base-build 100 --release-type patch --pr-updated 1234567890",
  ]
)

// MARK: - Argument parsing

struct Arguments {
  private let values: [String: String]

  init(_ raw: [String]) {
    var parsed: [String: String] = [:]
    var index = 0
    while index < raw.count {
      let key = raw[index]
      if key.hasPrefix("--") {
        let valueIndex = index + 1
        if valueIndex < raw.count, !raw[valueIndex].hasPrefix("--") {
          parsed[key] = raw[valueIndex]
          index += 2
          continue
        }
        parsed[key] = ""
        index += 1
      } else {
        index += 1
      }
    }
    values = parsed
  }

  func value(for key: String) -> String? { values[key] }

  func require(_ key: String) throws -> String {
    guard let value = values[key], !value.isEmpty else {
      throw ScriptError("Missing required argument: \(key)")
    }
    return value
  }
}

// MARK: - Version parsing

func extractValue(for key: String, in content: String) -> String? {
  let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*([^;]+);"
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let range = NSRange(content.startIndex..<content.endIndex, in: content)
  guard let match = regex.firstMatch(in: content, range: range),
    let valueRange = Range(match.range(at: 1), in: content)
  else { return nil }
  return String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}

func replacingValue(for key: String, with newValue: String, in content: String) throws -> String {
  let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*[^;]+;"
  let regex = try NSRegularExpression(pattern: pattern)
  let range = NSRange(content.startIndex..<content.endIndex, in: content)
  return regex.stringByReplacingMatches(
    in: content, range: range, withTemplate: "\(key) = \(newValue);")
}

func normalizedSemver(from raw: String) throws -> (major: Int, minor: Int, patch: Int) {
  let parts = raw.split(separator: ".").map { String($0) }
  guard !parts.isEmpty else { throw ScriptError("Empty version string") }
  let numeric = parts.map { Int($0) ?? 0 }
  var padded = numeric
  while padded.count < 3 { padded.append(0) }
  let trimmed = Array(padded.prefix(3))
  return (trimmed[0], trimmed[1], trimmed[2])
}

func bumpVersion(
  _ version: (major: Int, minor: Int, patch: Int),
  releaseType: String
) throws -> (major: Int, minor: Int, patch: Int) {
  switch releaseType.lowercased() {
  case "major": return (version.major + 1, 0, 0)
  case "minor": return (version.major, version.minor + 1, 0)
  case "patch": return (version.major, version.minor, version.patch + 1)
  default: throw ScriptError("Unknown release type: \(releaseType)")
  }
}

// MARK: - PR body parsing

func releaseType(from body: String) -> String {
  func isChecked(_ label: String) -> Bool {
    let pattern = "- \\[x\\]\\s*\(NSRegularExpression.escapedPattern(for: label))"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return false
    }
    let range = NSRange(body.startIndex..<body.endIndex, in: body)
    return regex.firstMatch(in: body, range: range) != nil
  }
  if isChecked(Constants.releaseTypeMajor) { return "major" }
  if isChecked(Constants.releaseTypeMinor) { return "minor" }
  return "patch"
}

func epochSeconds(from iso8601: String) throws -> Int {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: iso8601) { return Int(date.timeIntervalSince1970) }
  formatter.formatOptions = [.withInternetDateTime]
  if let date = formatter.date(from: iso8601) { return Int(date.timeIntervalSince1970) }
  throw ScriptError("Invalid ISO8601 timestamp: \(iso8601)")
}

func isHeading(_ line: String, heading: String) -> Bool {
  let pattern = "^#\\s*\(NSRegularExpression.escapedPattern(for: heading))\\s*$"
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return false
  }
  let range = NSRange(line.startIndex..<line.endIndex, in: line)
  return regex.firstMatch(in: line, range: range) != nil
}

func extractNotes(from body: String) -> String {
  let lines = body.components(separatedBy: .newlines)
  var inSection = false
  var collected: [String] = []
  for line in lines {
    if isHeading(line, heading: Constants.whatChangedHeading) {
      inSection = true
      continue
    }
    if inSection && isHeading(line, heading: Constants.releaseTypeHeading) { break }
    if inSection { collected.append(line) }
  }
  return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Metadata block

func metadataBlock(fromVersion: String, toVersion: String, fromBuild: String, toBuild: String)
  -> String
{
  [
    Constants.metadataStart,
    "---",
    "<small>Version information</small>",
    "<small><code>v\(fromVersion) (\(fromBuild))</code> → <code>v\(toVersion) (\(toBuild))</code></small>",
    Constants.metadataEnd,
  ].joined(separator: "\n")
}

func metadataRegex() throws -> NSRegularExpression {
  let start = NSRegularExpression.escapedPattern(for: Constants.metadataStart)
  let end = NSRegularExpression.escapedPattern(for: Constants.metadataEnd)
  return try NSRegularExpression(pattern: "\(start)[\\s\\S]*?\(end)")
}

func updatedBody(from body: String, with block: String) throws -> String {
  let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
  let regex = try metadataRegex()
  let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
  if regex.firstMatch(in: trimmed, range: range) != nil {
    return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: block)
  }
  return trimmed.isEmpty ? block : "\(trimmed)\n\n\(block)"
}

// MARK: - PR event loading

struct PullRequestEvent: Decodable {
  struct PullRequest: Decodable {
    let body: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
      case body
      case updatedAt = "updated_at"
    }
  }
  let pullRequest: PullRequest

  enum CodingKeys: String, CodingKey {
    case pullRequest = "pull_request"
  }
}

func loadPullRequestEvent(from path: String) throws -> PullRequestEvent {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  return try JSONDecoder().decode(PullRequestEvent.self, from: data)
}

// MARK: - Commands

func runRead(arguments: Arguments) throws {
  let path = try arguments.require("--path")
  let content = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
  guard let version = extractValue(for: Constants.marketingVersionKey, in: content) else {
    throw ScriptError("MARKETING_VERSION not found")
  }
  guard let build = extractValue(for: Constants.buildVersionKey, in: content) else {
    throw ScriptError("CURRENT_PROJECT_VERSION not found")
  }
  print("VERSION=\(version)")
  print("BUILD=\(build)")
}

func runBump(arguments: Arguments) throws {
  let path = try arguments.require("--path")
  let baseVersionRaw = try arguments.require("--base-version")
  let baseBuildRaw = try arguments.require("--base-build")
  let releaseType = try arguments.require("--release-type")
  let updatedRaw = try arguments.require("--pr-updated")

  guard let baseBuild = Int(baseBuildRaw) else {
    throw ScriptError("Invalid base build: \(baseBuildRaw)")
  }
  guard let updatedEpoch = Int(updatedRaw) else {
    throw ScriptError("Invalid pr-updated: \(updatedRaw)")
  }

  let fileURL = URL(fileURLWithPath: path)
  let content = try String(contentsOf: fileURL, encoding: .utf8)
  let baseVersion = try normalizedSemver(from: baseVersionRaw)
  let bumpedVersion = try bumpVersion(baseVersion, releaseType: releaseType)

  let fromVersion = "\(baseVersion.major).\(baseVersion.minor).\(baseVersion.patch)"
  let toVersion = "\(bumpedVersion.major).\(bumpedVersion.minor).\(bumpedVersion.patch)"

  // Build number = 30-minute increments since repo inception
  let repoInception = 1_751_838_521  // 2025-07-06 21:48:41 UTC (first commit)
  let halfHoursSinceInception = (updatedEpoch - repoInception) / 1800

  // If base build is already using the new format (< 100000), use max to handle multiple PRs in same 30-min window
  // Otherwise, ignore the old epoch-based format and start fresh with half-hours since inception
  let isNewFormat = baseBuild < 100000
  let toBuild = isNewFormat ? max(baseBuild + 1, halfHoursSinceInception) : halfHoursSinceInception

  let newContent = try replacingValue(
    for: Constants.marketingVersionKey, with: toVersion, in: content)
  let finalContent = try replacingValue(
    for: Constants.buildVersionKey, with: String(toBuild), in: newContent)

  if finalContent != content {
    try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  print("VERSION_FROM=\(fromVersion)")
  print("VERSION_TO=\(toVersion)")
  print("BUILD_FROM=\(baseBuild)")
  print("BUILD_TO=\(toBuild)")
}

func runPrInfo(arguments: Arguments) throws {
  let eventPath = try arguments.require("--event")
  let event = try loadPullRequestEvent(from: eventPath)
  let body = event.pullRequest.body ?? ""
  guard let updatedAt = event.pullRequest.updatedAt else {
    throw ScriptError("pull_request.updated_at missing")
  }
  print("RELEASE_TYPE=\(releaseType(from: body))")
  print("PR_UPDATED_EPOCH=\(try epochSeconds(from: updatedAt))")
}

func runExtractNotes(arguments: Arguments) throws {
  let eventPath = try arguments.require("--event")
  let event = try loadPullRequestEvent(from: eventPath)
  print(extractNotes(from: event.pullRequest.body ?? ""))
}

func runUpdateMetadata(arguments: Arguments) throws {
  let fromVersion = try arguments.require("--from-version")
  let toVersion = try arguments.require("--to-version")
  let fromBuild = try arguments.require("--from-build")
  let toBuild = try arguments.require("--to-build")

  let block = metadataBlock(
    fromVersion: fromVersion,
    toVersion: toVersion,
    fromBuild: fromBuild,
    toBuild: toBuild
  )
  let bodyData = FileHandle.standardInput.readDataToEndOfFile()
  let body = String(data: bodyData, encoding: .utf8) ?? ""
  print(try updatedBody(from: body, with: block))
}

// MARK: - Entry point

@main
struct VersionAndReleaseCommand {
  static func main() {
    runMain(usage: cli.usage()) {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()), scriptName: cli.scriptName)
      cli.preflight(args)
      guard let mode = args.first else { throw ScriptError("Missing mode argument") }

      guard let command = Command(rawValue: mode) else {
        throw ScriptError("Unknown mode: \(mode)")
      }

      let arguments = Arguments(Array(args.dropFirst()))

      switch command {
      case .read: try runRead(arguments: arguments)
      case .bump: try runBump(arguments: arguments)
      case .prInfo: try runPrInfo(arguments: arguments)
      case .extractNotes: try runExtractNotes(arguments: arguments)
      case .updateMetadata: try runUpdateMetadata(arguments: arguments)
      }
    }
  }
}
