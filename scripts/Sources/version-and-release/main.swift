// DESCRIPTION: Manage version tags and Github releases

import Common
import Foundation

// MARK: - Constants

enum Constants {
  static let marketingVersionKey = "MARKETING_VERSION"
  static let buildVersionKey = "CURRENT_PROJECT_VERSION"
  static let whatChangedHeading = "What changed?"
  static let releaseTypeHeading = "Release info"
  static let releaseTypeMajor = "Major"
  static let releaseTypeMinor = "Minor"
  static let prCommentMarker = "<!-- release-version -->"
}

// MARK: - CLI

enum Command: String, CLISubcommandType, CaseIterable {
  case read
  case bump
  case extractNotes = "extract-notes"
  case prComment = "pr-comment"

  var description: String {
    switch self {
    case .read: "Read version/build from project file"
    case .bump: "Bump PR branch (event + base ref + path)"
    case .extractNotes: "Extract release notes from PR body"
    case .prComment: "Upsert PR version comment (will-be|released)"
    }
  }
}

let cli = SimpleCLI(
  filePath: #filePath,
  subcommands: Command.allCases.map { ($0.rawValue, $0.description) },
  examples: [
    "run version-and-release read --path project.pbxproj",
    "run version-and-release bump --event event.json --path project.pbxproj --base-ref origin/main",
    "run version-and-release pr-comment --event event.json --version 2.0.0 --state will-be",
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

// MARK: - Latest tag

/// Returns the latest semantic version tag (e.g. v1.2.3) from the repo.
/// Caller must run `git fetch --tags` first.
func latestTagVersion() -> String? {
  guard
    let output = try? runCommand(
      "git", ["tag", "--list", "--sort=-v:refname"],
      emitOutput: false
    )
  else { return nil }
  let tags = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
  for tag in tags where !tag.isEmpty {
    let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let parts = trimmed.split(separator: ".").map { String($0) }
    guard parts.count >= 3,
      Int(parts[0]) != nil, Int(parts[1]) != nil, Int(parts[2]) != nil
    else { continue }
    return trimmed
  }
  return nil
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
  let eventPath = try arguments.require("--event")
  let path = try arguments.require("--path")
  let baseRef = try arguments.require("--base-ref")

  let event = try loadPullRequestEvent(from: eventPath)
  let body = event.pullRequest.body ?? ""
  guard let updatedAt = event.pullRequest.updatedAt else {
    throw ScriptError("pull_request.updated_at missing")
  }
  let releaseType = releaseType(from: body)
  let updatedEpoch = try epochSeconds(from: updatedAt)

  let baseContent = try runCommand(
    "git", ["show", "\(baseRef):\(path)"],
    emitOutput: false
  )
  guard let baseVersionRaw = extractValue(for: Constants.marketingVersionKey, in: baseContent),
    let baseBuildRaw = extractValue(for: Constants.buildVersionKey, in: baseContent)
  else {
    throw ScriptError("Could not read version/build from \(baseRef):\(path)")
  }
  guard let baseBuild = Int(baseBuildRaw) else {
    throw ScriptError("Invalid base build: \(baseBuildRaw)")
  }

  let versionBase = latestTagVersion() ?? baseVersionRaw
  let versionSemver = try normalizedSemver(from: versionBase)
  let bumpedSemver = try bumpVersion(versionSemver, releaseType: releaseType)
  let fromVersion = versionBase
  let toVersion = "\(bumpedSemver.major).\(bumpedSemver.minor).\(bumpedSemver.patch)"

  let repoInception = 1_751_838_521
  let halfHoursSinceInception = (updatedEpoch - repoInception) / 1800
  let isNewFormat = baseBuild < 100000
  let toBuild = isNewFormat ? max(baseBuild + 1, halfHoursSinceInception) : halfHoursSinceInception

  let fileURL = URL(fileURLWithPath: path)
  let content = try String(contentsOf: fileURL, encoding: .utf8)
  let newContent = try replacingValue(
    for: Constants.marketingVersionKey, with: toVersion, in: content)
  let finalContent = try replacingValue(
    for: Constants.buildVersionKey, with: String(toBuild), in: newContent)

  let changed = finalContent != content
  if changed {
    try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  print("VERSION_FROM=\(fromVersion)")
  print("VERSION_TO=\(toVersion)")
  print("BUILD_FROM=\(baseBuild)")
  print("BUILD_TO=\(toBuild)")
  print("CHANGED=\(changed ? "1" : "0")")
}

func runExtractNotes(arguments: Arguments) throws {
  let eventPath = try arguments.require("--event")
  let event = try loadPullRequestEvent(from: eventPath)
  print(extractNotes(from: event.pullRequest.body ?? ""))
}

func runPrComment(arguments: Arguments) throws {
  let eventPath = try arguments.require("--event")
  let version = try arguments.require("--version")
  let stateRaw = try arguments.require("--state")
  guard stateRaw == "will-be" || stateRaw == "released" else {
    throw ScriptError("--state must be 'will-be' or 'released'")
  }
  let isReleased = stateRaw == "released"
  let releaseUrl = ProcessInfo.processInfo.environment["RELEASE_URL"]

  if isReleased && (releaseUrl == nil || releaseUrl?.isEmpty == true) {
    throw ScriptError("RELEASE_URL environment variable required when state is 'released'")
  }

  let (owner, repo, issueNumber) = try loadExtendedEvent(from: eventPath)

  let marker = Constants.prCommentMarker
  let body: String
  if isReleased, let url = releaseUrl {
    body =
      "\(marker)\n🎉 This PR is included in version \(version) 🎉\n\nThe release is available on [GitHub release](\(url))"
  } else {
    body = "\(marker)\n🎉 This PR will be included in version \(version) 🎉"
  }

  guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty else {
    throw ScriptError("GITHUB_TOKEN environment variable required")
  }

  try upsertPrComment(
    owner: owner, repo: repo, issueNumber: issueNumber, body: body, token: token, marker: marker)
}

// MARK: - GitHub API

func loadExtendedEvent(from path: String) throws -> (owner: String, repo: String, issueNumber: Int)
{
  struct EventPayload: Decodable {
    let repository: Repo?
    let pullRequest: PR?

    enum CodingKeys: String, CodingKey {
      case repository
      case pullRequest = "pull_request"
    }

    struct Repo: Decodable {
      let owner: Owner?
      let name: String?
      struct Owner: Decodable {
        let login: String?
      }
    }
    struct PR: Decodable {
      let number: Int
    }
  }
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  let payload = try JSONDecoder().decode(EventPayload.self, from: data)
  guard let repo = payload.repository,
    let owner = repo.owner?.login, !owner.isEmpty,
    let name = repo.name, !name.isEmpty,
    let pr = payload.pullRequest
  else {
    throw ScriptError("Missing repository or pull request info in event payload")
  }
  return (owner, name, pr.number)
}

func urlSessionSyncData(for request: URLRequest) throws -> (Data, URLResponse) {
  var result: (Data?, URLResponse?, Error?)?
  let semaphore = DispatchSemaphore(value: 0)
  URLSession.shared.dataTask(with: request) { data, response, error in
    result = (data, response, error)
    semaphore.signal()
  }.resume()
  semaphore.wait()
  guard let r = result else { throw ScriptError("URLSession data task did not complete") }
  if let error = r.2 { throw error }
  guard let data = r.0, let response = r.1 else {
    throw ScriptError("URLSession returned nil data or response")
  }
  return (data, response)
}

func upsertPrComment(
  owner: String, repo: String, issueNumber: Int, body: String, token: String, marker: String
)
  throws
{
  let base = "https://api.github.com"
  var request = URLRequest(
    url: URL(string: "\(base)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments?per_page=100")!)
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")

  let (data, response) = try urlSessionSyncData(for: request)
  guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
    let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
    throw ScriptError("GitHub API error: \(msg)")
  }

  struct Comment: Decodable {
    let id: Int
    let body: String?
  }
  struct CommentList: Decodable {
    let list: [Comment]
    init(from decoder: Decoder) throws {
      list = try [Comment](from: decoder)
    }
  }
  let comments = try JSONDecoder().decode([Comment].self, from: data)
  let existing = comments.first { ($0.body ?? "").contains(marker) }

  if let comment = existing {
    var patchRequest = URLRequest(
      url: URL(string: "\(base)/repos/\(owner)/\(repo)/issues/comments/\(comment.id)")!)
    patchRequest.httpMethod = "PATCH"
    patchRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    patchRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    patchRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    patchRequest.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
    let (patchData, patchResponse) = try urlSessionSyncData(for: patchRequest)
    guard let patchHttp = patchResponse as? HTTPURLResponse,
      (200...299).contains(patchHttp.statusCode)
    else {
      let msg = String(data: patchData, encoding: .utf8) ?? "Unknown error"
      throw ScriptError("GitHub API PATCH error: \(msg)")
    }
  } else {
    var postRequest = URLRequest(
      url: URL(string: "\(base)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments")!)
    postRequest.httpMethod = "POST"
    postRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    postRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    postRequest.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
    let (postData, postResponse) = try urlSessionSyncData(for: postRequest)
    guard let postHttp = postResponse as? HTTPURLResponse, (200...299).contains(postHttp.statusCode)
    else {
      let msg = String(data: postData, encoding: .utf8) ?? "Unknown error"
      throw ScriptError("GitHub API POST error: \(msg)")
    }
  }
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
      case .extractNotes: try runExtractNotes(arguments: arguments)
      case .prComment: try runPrComment(arguments: arguments)
      }
    }
  }
}
