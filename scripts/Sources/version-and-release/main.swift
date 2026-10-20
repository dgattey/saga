// DESCRIPTION: Manage version tags and Github releases

import Common
import Foundation

// MARK: - Constants

enum Constants {
  static let marketingVersionKey = "MARKETING_VERSION"
  static let buildVersionKey = "CURRENT_PROJECT_VERSION"
  static let releaseNotesHeading = "Release notes"
  static let highlightsHeading = "Highlights"
  static let summaryHeading = "Summary"
  static let overviewHeading = "Overview"
  static let whatChangedHeading = "What changed?"
  static let changesHeading = "Changes"
  static let descriptionHeading = "Description"
  static let releaseTypeHeading = "Release info"
  static let releaseTypeMajor = "Major"
  static let releaseTypeMinor = "Minor"
  static let prCommentMarker = "<!-- release-version -->"
}

// MARK: - CLI

enum Command: String, CLISubcommandType, CaseIterable {
  case read
  case extractNotes = "extract-notes"
  case prComment = "pr-comment"
  case package

  var description: String {
    switch self {
    case .read: "Read or compute version/build from project file and optional release event"
    case .extractNotes: "Extract release notes from PR body"
    case .prComment: "Upsert PR version comment (will-be|released)"
    case .package: "Build, sign, zip, and generate Sparkle appcast.xml for macOS release"
    }
  }
}

let cli = SimpleCLI(
  filePath: #filePath,
  subcommands: Command.allCases.map { ($0.rawValue, $0.description) },
  examples: [
    "run version-and-release read --path project.pbxproj",
    "run version-and-release read --path project.pbxproj --event event.json",
    "run version-and-release pr-comment --event event.json --version 2.0.0 --state released",
    "run version-and-release package --version 2.1.0 --build 1042 --output-dir dist/release",
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

func isSemverHigher(
  _ lhs: (major: Int, minor: Int, patch: Int),
  than rhs: (major: Int, minor: Int, patch: Int)
) -> Bool {
  (lhs.major, lhs.minor, lhs.patch) > (rhs.major, rhs.minor, rhs.patch)
}

func maxSemver(
  _ lhs: (major: Int, minor: Int, patch: Int),
  _ rhs: (major: Int, minor: Int, patch: Int)
) -> (major: Int, minor: Int, patch: Int) {
  isSemverHigher(lhs, than: rhs) ? lhs : rhs
}

func formatSemver(_ version: (major: Int, minor: Int, patch: Int)) -> String {
  "\(version.major).\(version.minor).\(version.patch)"
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
    let pattern = "^\\s*-\\s*\\[x\\]\\s*\(NSRegularExpression.escapedPattern(for: label))\\b"
    guard
      let regex = try? NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    else {
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

func headingLevel(of line: String) -> Int? {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  guard trimmed.hasPrefix("#") else { return nil }
  let hashes = trimmed.prefix { $0 == "#" }
  let remainder = trimmed.dropFirst(hashes.count)
  guard let first = remainder.first, first.isWhitespace else { return nil }
  let title = remainder.trimmingCharacters(in: .whitespaces)
  guard !title.isEmpty else { return nil }
  return hashes.count
}

func isHeading(_ line: String, heading: String) -> Int? {
  guard let level = headingLevel(of: line) else { return nil }
  let pattern = "^#+\\s*\(NSRegularExpression.escapedPattern(for: heading))\\s*:?\\s*$"
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return nil
  }
  let range = NSRange(line.startIndex..<line.endIndex, in: line)
  return regex.firstMatch(in: line, range: range) != nil ? level : nil
}

func isStoppedSubheading(_ line: String) -> Bool {
  let stopNames = [
    "Verification",
    "Testing",
    "Test plan",
    "Tests",
    "Screenshots",
    "Demo",
    "Checklist",
    Constants.releaseTypeHeading,
  ]
  return stopNames.contains { isHeading(line, heading: $0) != nil }
}

func stripAgentWrapper(from body: String) -> String {
  var cleaned = body
  if let beginRange = cleaned.range(of: "<!-- CURSOR_AGENT_PR_BODY_BEGIN -->") {
    cleaned = String(cleaned[beginRange.upperBound...])
  }
  if let endRange = cleaned.range(of: "<!-- CURSOR_AGENT_PR_BODY_END -->") {
    cleaned = String(cleaned[..<endRange.lowerBound])
  }
  // Remove HTML comments
  if let commentRegex = try? NSRegularExpression(pattern: "<!--\\s*[\\s\\S]*?\\s*-->") {
    let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
    cleaned = commentRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
  }
  return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

func extractSection(
  named heading: String,
  from body: String,
  includeSubsections: Bool = true
) -> String {
  let cleanedBody = stripAgentWrapper(from: body)
  let lines = cleanedBody.components(separatedBy: .newlines)
  var sectionLevel: Int?
  var skippingSubheadingLevel: Int?
  var collected: [String] = []
  for line in lines {
    if let matchedLevel = isHeading(line, heading: heading), sectionLevel == nil {
      sectionLevel = matchedLevel
      continue
    }
    guard let activeLevel = sectionLevel else { continue }

    if line.range(of: "^-+\\s*$", options: .regularExpression) != nil {
      break
    }

    if let currentHeadingLevel = headingLevel(of: line) {
      if currentHeadingLevel <= activeLevel {
        break
      }
      if !includeSubsections || isStoppedSubheading(line) {
        skippingSubheadingLevel = currentHeadingLevel
        continue
      }
      if let skipLevel = skippingSubheadingLevel, currentHeadingLevel <= skipLevel {
        skippingSubheadingLevel = nil
      }
    }

    if skippingSubheadingLevel != nil {
      continue
    }

    if line.range(of: "^\\s*[-*]\\s*$", options: .regularExpression) != nil {
      continue
    }
    collected.append(line)
  }
  return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

func extractFallbackBody(from body: String) -> String {
  let cleanedBody = stripAgentWrapper(from: body)
  let lines = cleanedBody.components(separatedBy: .newlines)
  var skippingHeadingLevel: Int?
  var collected: [String] = []

  for line in lines {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.range(of: "^(?i)(closes|fixes|resolves)\\b", options: .regularExpression) != nil {
      continue
    }
    if let level = headingLevel(of: line) {
      if isStoppedSubheading(line) {
        skippingHeadingLevel = level
        continue
      }
      if let skipLevel = skippingHeadingLevel, level <= skipLevel {
        skippingHeadingLevel = nil
      }
      continue
    }
    if skippingHeadingLevel != nil {
      continue
    }
    if trimmed.range(of: "^-\\s*\\[[ xX]\\]\\s*", options: .regularExpression) != nil {
      continue
    }
    if trimmed.range(of: "^[-*]\\s*$", options: .regularExpression) != nil {
      continue
    }
    collected.append(line)
  }
  return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

func extractNotes(from body: String, title: String? = nil, preferConcise: Bool = false) -> String {
  let headings =
    preferConcise
    ? [
      Constants.releaseNotesHeading,
      Constants.highlightsHeading,
      Constants.summaryHeading,
      Constants.overviewHeading,
      Constants.whatChangedHeading,
      Constants.changesHeading,
      Constants.descriptionHeading,
    ]
    : [
      Constants.releaseNotesHeading,
      Constants.highlightsHeading,
      Constants.whatChangedHeading,
      Constants.summaryHeading,
      Constants.changesHeading,
      Constants.overviewHeading,
      Constants.descriptionHeading,
    ]
  for heading in headings {
    // For concise Sparkle notes, prefer the top-level Summary prose before falling back to
    // nested `### Changes` implementation details when `## Summary` has prose.
    if preferConcise && heading == Constants.summaryHeading {
      let summaryTopOnly = extractSection(named: heading, from: body, includeSubsections: false)
      if !summaryTopOnly.isEmpty {
        return summaryTopOnly
      }
    }
    let section = extractSection(named: heading, from: body, includeSubsections: true)
    if !section.isEmpty {
      return section
    }
  }
  let fallback = extractFallbackBody(from: body)
  if !fallback.isEmpty {
    return fallback
  }
  if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
    return "- \(title)"
  }
  return ""
}

// MARK: - Latest tag

/// Returns all semantic version tags sorted descending by version.
/// Caller must run `git fetch --tags` first.
func allSemverTags() -> [(major: Int, minor: Int, patch: Int)] {
  guard
    let output = try? runCommand(
      "git", ["tag", "--list", "--sort=-v:refname"],
      emitOutput: false
    )
  else { return [] }
  let tags = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
  var result: [(major: Int, minor: Int, patch: Int)] = []
  for tag in tags where !tag.isEmpty {
    let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let parts = trimmed.split(separator: ".").map { String($0) }
    guard parts.count >= 3,
      let major = Int(parts[0]),
      let minor = Int(parts[1]),
      let patch = Int(parts[2])
    else { continue }
    result.append((major, minor, patch))
  }
  return result
}

/// Queries the latest published appcast.xml to find the highest live Sparkle build number.
func latestAppcastBuildNumber(repoSlug: String) -> Int? {
  guard !repoSlug.isEmpty,
    let url = URL(string: "https://github.com/\(repoSlug)/releases/latest/download/appcast.xml")
  else { return nil }
  var request = URLRequest(url: url)
  request.timeoutInterval = 10
  guard let (data, response) = try? urlSessionSyncData(for: request),
    let http = response as? HTTPURLResponse,
    (200...299).contains(http.statusCode),
    let xml = String(data: data, encoding: .utf8)
  else { return nil }
  let pattern = "<sparkle:version>\\s*(\\d+)\\s*</sparkle:version>"
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
  let matches = regex.matches(in: xml, range: range)
  var highest: Int?
  for match in matches {
    guard let valueRange = Range(match.range(at: 1), in: xml),
      let buildNum = Int(xml[valueRange])
    else { continue }
    if let current = highest {
      highest = max(current, buildNum)
    } else {
      highest = buildNum
    }
  }
  return highest
}

// MARK: - PR event loading

struct PullRequestEvent: Decodable {
  struct PullRequest: Decodable {
    let title: String?
    let body: String?
    let mergedAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
      case title
      case body
      case mergedAt = "merged_at"
      case updatedAt = "updated_at"
    }
  }
  struct Repository: Decodable {
    struct Owner: Decodable {
      let login: String?
    }
    let owner: Owner?
    let name: String?
  }
  let pullRequest: PullRequest
  let repository: Repository?

  enum CodingKeys: String, CodingKey {
    case pullRequest = "pull_request"
    case repository
  }
}

func loadPullRequestEvent(from path: String) throws -> PullRequestEvent {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  return try JSONDecoder().decode(PullRequestEvent.self, from: data)
}

// MARK: - Commands

func runRead(arguments: Arguments) throws {
  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let defaultPbxproj = "\(repoRoot)/Saga/Saga.xcodeproj/project.pbxproj"
  let path: String
  if let customPath = arguments.value(for: "--path"), !customPath.isEmpty {
    path = customPath
  } else {
    path = defaultPbxproj
  }
  let fileURL = URL(fileURLWithPath: path)
  let content = try String(contentsOf: fileURL, encoding: .utf8)
  guard var version = extractValue(for: Constants.marketingVersionKey, in: content) else {
    throw ScriptError("MARKETING_VERSION not found")
  }
  guard var build = extractValue(for: Constants.buildVersionKey, in: content) else {
    throw ScriptError("CURRENT_PROJECT_VERSION not found")
  }

  if let eventPath = arguments.value(for: "--event"), !eventPath.isEmpty {
    let event = try loadPullRequestEvent(from: eventPath)
    let selectedReleaseType = releaseType(from: event.pullRequest.body ?? "")
    let currentSemver = try normalizedSemver(from: version)
    let pbxprojBuild = Int(build) ?? 1
    let semverTags = allSemverTags()

    let resolvedSemver: (major: Int, minor: Int, patch: Int)
    let alreadyBumpedInPbxproj: Bool
    if let latestTag = semverTags.first {
      alreadyBumpedInPbxproj = isSemverHigher(currentSemver, than: latestTag)
      let bumpedFromTag = try bumpVersion(latestTag, releaseType: selectedReleaseType)
      resolvedSemver = maxSemver(currentSemver, bumpedFromTag)
    } else {
      alreadyBumpedInPbxproj = false
      resolvedSemver = try bumpVersion(currentSemver, releaseType: selectedReleaseType)
    }
    let resolvedVersion = formatSemver(resolvedSemver)

    // Compute a strictly increasing Sparkle build number across sequential merges:
    // 1. Half-hours since repo inception (preserves Saga's 22xxx build scale)
    // 2. pbxproj build + count of tags newer than pbxproj + 1 (if not already bumped in pbxproj)
    // 3. Live appcast.xml sparkle:version + 1 (if reachable)
    let repoInception = 1_751_838_521
    let eventEpoch =
      (event.pullRequest.mergedAt.flatMap { try? epochSeconds(from: $0) })
      ?? (event.pullRequest.updatedAt.flatMap { try? epochSeconds(from: $0) })
      ?? Int(Date().timeIntervalSince1970)
    let halfHoursSinceInception = (eventEpoch - repoInception) / 1800

    let tagsNewerThanPbxproj = semverTags.filter { isSemverHigher($0, than: currentSemver) }.count
    let pbxprojFloor =
      alreadyBumpedInPbxproj
      ? pbxprojBuild
      : (pbxprojBuild + tagsNewerThanPbxproj + 1)

    let envRepo = ProcessInfo.processInfo.environment["SAGA_REPO"] ?? "dgattey/saga"
    let eventRepo: String? = {
      guard let owner = event.repository?.owner?.login, !owner.isEmpty,
        let name = event.repository?.name, !name.isEmpty
      else { return nil }
      return "\(owner)/\(name)"
    }()
    let repoSlug = eventRepo ?? envRepo
    let liveAppcastFloor = (latestAppcastBuildNumber(repoSlug: repoSlug) ?? -1) + 1

    let resolvedBuild = String(max(pbxprojFloor, halfHoursSinceInception, liveAppcastFloor))
    if resolvedVersion != version || resolvedBuild != build {
      let updatedVersionContent = try replacingValue(
        for: Constants.marketingVersionKey, with: resolvedVersion, in: content)
      let updatedContent = try replacingValue(
        for: Constants.buildVersionKey, with: resolvedBuild, in: updatedVersionContent)
      try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
      version = resolvedVersion
      build = resolvedBuild
    }
  }

  print("VERSION=\(version)")
  print("BUILD=\(build)")
}

func runExtractNotes(arguments: Arguments) throws {
  let eventPath = try arguments.require("--event")
  let preferConcise = arguments.value(for: "--sparkle") != nil
  let event = try loadPullRequestEvent(from: eventPath)
  print(
    extractNotes(
      from: event.pullRequest.body ?? "",
      title: event.pullRequest.title,
      preferConcise: preferConcise
    )
  )
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

func runPackage(arguments: Arguments) throws {
  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let defaultPbxproj = "\(repoRoot)/Saga/Saga.xcodeproj/project.pbxproj"
  let pbxprojPath = arguments.value(for: "--path") ?? defaultPbxproj

  let version: String
  let build: String
  if let v = arguments.value(for: "--version"), !v.isEmpty,
    let b = arguments.value(for: "--build"), !b.isEmpty
  {
    version = v
    build = b
  } else {
    let content = try String(contentsOf: URL(fileURLWithPath: pbxprojPath), encoding: .utf8)
    guard let v = extractValue(for: Constants.marketingVersionKey, in: content),
      let b = extractValue(for: Constants.buildVersionKey, in: content)
    else {
      throw ScriptError(
        "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from \(pbxprojPath)")
    }
    version = arguments.value(for: "--version") ?? v
    build = arguments.value(for: "--build") ?? b
  }

  let outputDir = arguments.value(for: "--output-dir") ?? "\(repoRoot)/dist/release"
  let scriptPath = "\(repoRoot)/scripts/package-release.sh"
  try runCommand(
    scriptPath,
    [version, build, outputDir],
    cwd: URL(fileURLWithPath: repoRoot)
  )
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
  nonisolated(unsafe) var result: (Data?, URLResponse?, Error?)?
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
  guard
    let listURL = URL(
      string: "\(base)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments?per_page=100")
  else {
    throw ScriptError("Invalid GitHub comments URL")
  }
  var request = URLRequest(url: listURL)
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
  let comments = try JSONDecoder().decode([Comment].self, from: data)
  let existing = comments.first { ($0.body ?? "").contains(marker) }

  if let comment = existing {
    guard
      let patchURL = URL(
        string: "\(base)/repos/\(owner)/\(repo)/issues/comments/\(comment.id)")
    else {
      throw ScriptError("Invalid GitHub comment PATCH URL")
    }
    var patchRequest = URLRequest(url: patchURL)
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
    guard
      let postURL = URL(
        string: "\(base)/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments")
    else {
      throw ScriptError("Invalid GitHub comment POST URL")
    }
    var postRequest = URLRequest(url: postURL)
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
      case .extractNotes: try runExtractNotes(arguments: arguments)
      case .prComment: try runPrComment(arguments: arguments)
      case .package: try runPackage(arguments: arguments)
      }
    }
  }
}
