#!/usr/bin/env swift

import Foundation

// Lightweight helper used by GitHub Actions for versioning.

struct Constants {
    static let marketingVersionKey = "MARKETING_VERSION"
    static let buildVersionKey = "CURRENT_PROJECT_VERSION"
    static let metadataStart = "<!-- release-metadata-start -->"
    static let metadataEnd = "<!-- release-metadata-end -->"
    static let whatChangedHeading = "What changed?"
    static let releaseTypeHeading = "Release info"
    static let releaseTypeMajor = "Major"
    static let releaseTypeMinor = "Minor"
    static let releaseTypePatch = "Patch"
}

enum VersioningError: Error {
    case missingArgument(String)
    case invalidArgument(String)
    case parseFailed(String)
}

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

    func value(for key: String) -> String? {
        values[key]
    }
}

func usage() -> String {
    """
    Usage:
      versioning.swift read --path <pbxproj>
      versioning.swift bump --path <pbxproj> --base-version <x.y.z> --base-build <n> --release-type <major|minor|patch> --pr-updated <epochSeconds>
      versioning.swift pr-info --event <event-json-path>
      versioning.swift extract-notes --event <event-json-path>
      versioning.swift update-metadata --from-version <x.y.z> --to-version <x.y.z> --from-build <n> --to-build <n> --release-type <major|minor|patch>
      versioning.swift metadata-block --from-version <x.y.z> --to-version <x.y.z> --from-build <n> --to-build <n> --release-type <major|minor|patch>
    """
}

func requireValue(_ key: String, in arguments: Arguments) throws -> String {
    guard let value = arguments.value(for: key), !value.isEmpty else {
        throw VersioningError.missingArgument(key)
    }
    return value
}

// Extracts build settings values from the project file.
func extractValue(for key: String, in content: String) -> String? {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*([^;]+);"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    guard let match = regex.firstMatch(in: content, range: range),
          let valueRange = Range(match.range(at: 1), in: content) else {
        return nil
    }
    return String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}

// Replaces build settings values in the project file.
func replacingValue(for key: String, with newValue: String, in content: String) throws -> String {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*[^;]+;"
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let replacement = "\(key) = \(newValue);"
    return regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
}

// Normalizes short versions like "1.0" into full semver tuples.
func normalizedSemver(from raw: String) throws -> (major: Int, minor: Int, patch: Int) {
    let parts = raw.split(separator: ".").map { String($0) }
    guard !parts.isEmpty else {
        throw VersioningError.parseFailed("Empty version string")
    }
    let numeric = parts.map { Int($0) ?? 0 }
    var padded = numeric
    while padded.count < 3 {
        padded.append(0)
    }
    let trimmed = Array(padded.prefix(3))
    return (trimmed[0], trimmed[1], trimmed[2])
}

func bumpVersion(_ version: (major: Int, minor: Int, patch: Int), releaseType: String) throws -> (major: Int, minor: Int, patch: Int) {
    switch releaseType.lowercased() {
    case "major":
        return (version.major + 1, 0, 0)
    case "minor":
        return (version.major, version.minor + 1, 0)
    case "patch":
        return (version.major, version.minor, version.patch + 1)
    default:
        throw VersioningError.invalidArgument("Unknown release type: \(releaseType)")
    }
}

// Determines release type from PR checkbox section with precedence.
func releaseType(from body: String) -> String {
    func isChecked(_ label: String) -> Bool {
        let pattern = "- \\[x\\]\\s*\(NSRegularExpression.escapedPattern(for: label))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.firstMatch(in: body, range: range) != nil
    }
    if isChecked(Constants.releaseTypeMajor) {
        return "major"
    }
    if isChecked(Constants.releaseTypeMinor) {
        return "minor"
    }
    if isChecked(Constants.releaseTypePatch) {
        return "patch"
    }
    return "patch"
}

// Converts GitHub's ISO8601 timestamps into epoch seconds.
func epochSeconds(from iso8601: String) throws -> Int {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: iso8601) {
        return Int(date.timeIntervalSince1970)
    }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: iso8601) {
        return Int(date.timeIntervalSince1970)
    }
    throw VersioningError.invalidArgument("Invalid ISO8601 timestamp: \(iso8601)")
}

func metadataBlock(fromVersion: String, toVersion: String, fromBuild: String, toBuild: String, releaseType: String) -> String {
    [
        Constants.metadataStart,
        "---",
        "<small><code>Version information</code></small>",
        "<small><code>v\(fromVersion) (\(fromBuild)) -> v\(toVersion) (\(toBuild))</code></small>",
        Constants.metadataEnd
    ].joined(separator: "\n")
}

func metadataRegex() throws -> NSRegularExpression {
    let start = NSRegularExpression.escapedPattern(for: Constants.metadataStart)
    let end = NSRegularExpression.escapedPattern(for: Constants.metadataEnd)
    let pattern = "\(start)[\\s\\S]*?\(end)"
    return try NSRegularExpression(pattern: pattern)
}

func updatedBody(from body: String, with metadataBlock: String) throws -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let regex = try metadataRegex()
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    if regex.firstMatch(in: trimmed, range: range) != nil {
        return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: metadataBlock)
    }
    if trimmed.isEmpty {
        return metadataBlock
    }
    return "\(trimmed)\n\n\(metadataBlock)"
}

func isHeading(_ line: String, heading: String) -> Bool {
    let pattern = "^#\\s*\(NSRegularExpression.escapedPattern(for: heading))\\s*$"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return false
    }
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    return regex.firstMatch(in: line, range: range) != nil
}

// Extracts the "What changed?" section from a PR body.
func extractNotes(from body: String) -> String {
    let lines = body.components(separatedBy: .newlines)
    var inSection = false
    var collected: [String] = []
    for line in lines {
        if isHeading(line, heading: Constants.whatChangedHeading) {
            inSection = true
            continue
        }
        if inSection && isHeading(line, heading: Constants.releaseTypeHeading) {
            break
        }
        if inSection {
            collected.append(line)
        }
    }
    return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

struct PullRequestEvent: Decodable {
    struct PullRequest: Decodable {
        let body: String?
        let updated_at: String?
    }
    let pull_request: PullRequest
}

func loadPullRequestEvent(from path: String) throws -> PullRequestEvent {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(PullRequestEvent.self, from: data)
}

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let mode = args.first else {
        throw VersioningError.missingArgument("mode")
    }

    let arguments = Arguments(Array(args.dropFirst()))

    switch mode {
    case "read":
        let path = try requireValue("--path", in: arguments)
        let fileURL = URL(fileURLWithPath: path)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        guard let version = extractValue(for: Constants.marketingVersionKey, in: content) else {
            throw VersioningError.parseFailed("MARKETING_VERSION not found")
        }
        guard let build = extractValue(for: Constants.buildVersionKey, in: content) else {
            throw VersioningError.parseFailed("CURRENT_PROJECT_VERSION not found")
        }
        print("VERSION=\(version)")
        print("BUILD=\(build)")

    case "bump":
        let path = try requireValue("--path", in: arguments)
        let baseVersionRaw = try requireValue("--base-version", in: arguments)
        let baseBuildRaw = try requireValue("--base-build", in: arguments)
        let releaseType = try requireValue("--release-type", in: arguments)
        let updatedRaw = try requireValue("--pr-updated", in: arguments)

        guard let baseBuild = Int(baseBuildRaw) else {
            throw VersioningError.invalidArgument("Invalid base build: \(baseBuildRaw)")
        }
        guard let updatedEpoch = Int(updatedRaw) else {
            throw VersioningError.invalidArgument("Invalid pr-updated: \(updatedRaw)")
        }

        let fileURL = URL(fileURLWithPath: path)
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        let baseVersion = try normalizedSemver(from: baseVersionRaw)
        let bumpedVersion = try bumpVersion(baseVersion, releaseType: releaseType)

        let fromVersion = "\(baseVersion.major).\(baseVersion.minor).\(baseVersion.patch)"
        let toVersion = "\(bumpedVersion.major).\(bumpedVersion.minor).\(bumpedVersion.patch)"

        let toBuild = max(baseBuild + 1, updatedEpoch)
        let newContent = try replacingValue(for: Constants.marketingVersionKey, with: toVersion, in: content)
        let finalContent = try replacingValue(for: Constants.buildVersionKey, with: String(toBuild), in: newContent)

        if finalContent != content {
            try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        print("VERSION_FROM=\(fromVersion)")
        print("VERSION_TO=\(toVersion)")
        print("BUILD_FROM=\(baseBuild)")
        print("BUILD_TO=\(toBuild)")
        print("RELEASE_TYPE=\(releaseType.lowercased())")

    case "pr-info":
        let eventPath = try requireValue("--event", in: arguments)
        let event = try loadPullRequestEvent(from: eventPath)
        let body = event.pull_request.body ?? ""
        guard let updatedAt = event.pull_request.updated_at else {
            throw VersioningError.parseFailed("pull_request.updated_at missing")
        }
        let release = releaseType(from: body)
        let updatedEpoch = try epochSeconds(from: updatedAt)
        print("RELEASE_TYPE=\(release)")
        print("PR_UPDATED_EPOCH=\(updatedEpoch)")

    case "extract-notes":
        let eventPath = try requireValue("--event", in: arguments)
        let event = try loadPullRequestEvent(from: eventPath)
        let body = event.pull_request.body ?? ""
        let notes = extractNotes(from: body)
        print(notes)

    case "update-metadata":
        let fromVersion = try requireValue("--from-version", in: arguments)
        let toVersion = try requireValue("--to-version", in: arguments)
        let fromBuild = try requireValue("--from-build", in: arguments)
        let toBuild = try requireValue("--to-build", in: arguments)
        let releaseType = try requireValue("--release-type", in: arguments)
        let block = metadataBlock(fromVersion: fromVersion, toVersion: toVersion, fromBuild: fromBuild, toBuild: toBuild, releaseType: releaseType)
        let bodyData = FileHandle.standardInput.readDataToEndOfFile()
        let body = String(data: bodyData, encoding: .utf8) ?? ""
        let updated = try updatedBody(from: body, with: block)
        print(updated)

    case "metadata-block":
        let fromVersion = try requireValue("--from-version", in: arguments)
        let toVersion = try requireValue("--to-version", in: arguments)
        let fromBuild = try requireValue("--from-build", in: arguments)
        let toBuild = try requireValue("--to-build", in: arguments)
        let releaseType = try requireValue("--release-type", in: arguments)
        print(metadataBlock(fromVersion: fromVersion, toVersion: toVersion, fromBuild: fromBuild, toBuild: toBuild, releaseType: releaseType))

    default:
        throw VersioningError.invalidArgument("Unknown mode: \(mode)")
    }
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data((usage() + "\nError: \(error)\n").utf8))
    exit(1)
}
