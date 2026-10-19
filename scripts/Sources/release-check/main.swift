// DESCRIPTION: Verify Sparkle appcasts (EdDSA signature, build floor, minimum macOS) before release

import Common
import CryptoKit
import Foundation

// MARK: - CLI

enum Command: String, CLISubcommandType, CaseIterable {
  case appcast
  case minOS = "min-os"

  var description: String {
    switch self {
    case .appcast:
      "Check every item's signature, archive length, minimum macOS, and build floor"
    case .minOS: "Print the macOS deployment target that appcasts must advertise"
    }
  }
}

let cli = SimpleCLI(
  filePath: #filePath,
  subcommands: Command.allCases.map { ($0.rawValue, $0.description) },
  examples: [
    "run release-check min-os",
    "run release-check appcast dist/release/appcast.xml --archive dist/release/Saga-1.6.1.zip",
    "run release-check appcast server/public/appcast.xml --download --no-live-feed",
    "run release-check appcast new.xml --download --live-feed https://example.com/previous.xml",
  ],
  notes: [
    "<appcast> and --live-feed accept a file path or an http(s) URL",
    "--archive <zip> verifies the item whose enclosure file name matches the zip",
    "--download fetches each enclosure over HTTP to verify it instead",
    "The live feed defaults to SUFeedURL in Info.plist; --no-live-feed skips the build floor",
    "Fails closed: an unsigned, unverified, or unreachable input is an error",
  ]
)

// MARK: - Project facts

struct Project {
  let publicKey: Curve25519.Signing.PublicKey
  let feedURL: URL
  let deploymentTarget: String

  static func load(repoRoot: String) throws -> Project {
    let plistPath = "\(repoRoot)/Saga/Saga/Config/Info.plist"
    let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    guard
      let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil)
        as? [String: Any]
    else { throw ScriptError("\(plistPath) is not a dictionary plist") }
    guard let encodedKey = plist["SUPublicEDKey"] as? String,
      let rawKey = Data(base64Encoded: encodedKey.trimmingCharacters(in: .whitespaces))
    else { throw ScriptError("SUPublicEDKey is missing or not base64 in \(plistPath)") }
    guard let feed = plist["SUFeedURL"] as? String, let feedURL = URL(string: feed) else {
      throw ScriptError("SUFeedURL is missing or invalid in \(plistPath)")
    }

    let pbxprojPath = "\(try findProjectPath(repoRoot: repoRoot))/project.pbxproj"
    let pbxproj = try String(contentsOfFile: pbxprojPath, encoding: .utf8)
    let targets = Set(
      pbxproj.matches(of: /MACOSX_DEPLOYMENT_TARGET = ([^;]+);/).map {
        String($0.1).trimmingCharacters(in: .whitespaces)
      })
    guard targets.count == 1, let deploymentTarget = targets.first else {
      throw ScriptError(
        "Expected one MACOSX_DEPLOYMENT_TARGET in \(pbxprojPath), found \(targets.sorted())")
    }

    return Project(
      publicKey: try Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
      feedURL: feedURL,
      deploymentTarget: deploymentTarget
    )
  }
}

// MARK: - Appcast model

struct AppcastItem {
  var shortVersion: String?
  var build: String?
  var minimumSystemVersion: String?
  var enclosureURL: URL?
  var length: String?
  var edSignature: String?

  var label: String { "\(shortVersion ?? "?") (\(build ?? "?"))" }
  var archiveName: String? { enclosureURL?.lastPathComponent }
}

final class AppcastParser: NSObject, XMLParserDelegate {
  private(set) var items: [AppcastItem] = []
  private var current: AppcastItem?
  private var text = ""

  static func parse(_ data: Data, source: String) throws -> [AppcastItem] {
    let delegate = AppcastParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else {
      throw ScriptError(
        "\(source) is not valid XML: \(parser.parserError?.localizedDescription ?? "unknown")")
    }
    guard !delegate.items.isEmpty else { throw ScriptError("\(source) has no <item> entries") }
    return delegate.items
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String] = [:]
  ) {
    text = ""
    if elementName == "item" {
      current = AppcastItem()
    } else if elementName == "enclosure", current != nil {
      current?.enclosureURL = attributes["url"].flatMap(URL.init(string:))
      current?.length = attributes["length"]
      current?.edSignature = attributes["sparkle:edSignature"]
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch elementName {
    case "sparkle:version": current?.build = value
    case "sparkle:shortVersionString": current?.shortVersion = value
    case "sparkle:minimumSystemVersion": current?.minimumSystemVersion = value
    case "item":
      if let item = current { items.append(item) }
      current = nil
    default: break
    }
  }
}

// MARK: - Checks

enum Violation: CustomStringConvertible {
  case unsigned
  case signatureUnverified
  case signatureInvalid
  case lengthMismatch(advertised: String?, actual: Int)
  case minimumSystemVersion(advertised: String?, deploymentTarget: String)
  case invalidBuild(String?)
  case buildNotAboveLive(build: Int, live: Int)

  var description: String {
    switch self {
    case .unsigned:
      "enclosure has no sparkle:edSignature"
    case .signatureUnverified:
      "sparkle:edSignature was not verified (pass --archive <zip> or --download)"
    case .signatureInvalid:
      "sparkle:edSignature does not verify against SUPublicEDKey"
    case .lengthMismatch(let advertised, let actual):
      "enclosure length \(advertised ?? "missing") does not match archive size \(actual)"
    case .minimumSystemVersion(let advertised, let deploymentTarget):
      "minimumSystemVersion \(advertised ?? "missing") does not match MACOSX_DEPLOYMENT_TARGET \(deploymentTarget)"
    case .invalidBuild(let build):
      "sparkle:version \(build ?? "missing") is not an integer build number"
    case .buildNotAboveLive(let build, let live):
      "build \(build) is not greater than live build \(live), so Sparkle never offers it"
    }
  }
}

func violations(
  for item: AppcastItem, archive: Data?, liveBuild: Int?, project: Project
) -> [Violation] {
  var found: [Violation] = []

  if let signature = item.edSignature {
    if let archive {
      let signatureData = Data(base64Encoded: signature) ?? Data()
      if !project.publicKey.isValidSignature(signatureData, for: archive) {
        found.append(.signatureInvalid)
      }
      if item.length != String(archive.count) {
        found.append(.lengthMismatch(advertised: item.length, actual: archive.count))
      }
    } else {
      found.append(.signatureUnverified)
    }
  } else {
    found.append(.unsigned)
  }

  if item.minimumSystemVersion != project.deploymentTarget {
    found.append(
      .minimumSystemVersion(
        advertised: item.minimumSystemVersion, deploymentTarget: project.deploymentTarget))
  }

  if let build = item.build.flatMap({ Int($0) }) {
    if let liveBuild, build <= liveBuild {
      found.append(.buildNotAboveLive(build: build, live: liveBuild))
    }
  } else {
    found.append(.invalidBuild(item.build))
  }

  return found
}

// MARK: - Inputs

func load(_ source: String) async throws -> Data {
  if let url = URL(string: source), url.scheme == "http" || url.scheme == "https" {
    return try await fetch(url)
  }
  return try Data(contentsOf: URL(fileURLWithPath: source))
}

func fetch(_ url: URL) async throws -> Data {
  let (data, response) = try await URLSession.shared.data(from: url)
  guard let http = response as? HTTPURLResponse else {
    throw ScriptError("GET \(url.absoluteString) returned no HTTP response")
  }
  guard (200..<300).contains(http.statusCode) else {
    throw ScriptError("GET \(url.absoluteString) returned HTTP \(http.statusCode)")
  }
  return data
}

enum LiveFeed {
  case project
  case source(String)
  case none
}

struct AppcastOptions {
  var appcast: String
  var archivePath: String?
  var download = false
  var liveFeed = LiveFeed.project

  init(_ args: [String]) throws {
    var appcast: String?
    var remaining = args[...]
    while let arg = remaining.popFirst() {
      switch arg {
      case "--archive":
        guard let value = remaining.popFirst() else { throw ScriptError("--archive needs a path") }
        archivePath = value
      case "--download":
        download = true
      case "--live-feed":
        guard let value = remaining.popFirst() else {
          throw ScriptError("--live-feed needs a path or URL")
        }
        liveFeed = .source(value)
      case "--no-live-feed":
        liveFeed = .none
      default:
        guard !arg.hasPrefix("--"), appcast == nil else {
          throw ScriptError("Unexpected argument: \(arg)")
        }
        appcast = arg
      }
    }
    guard let appcast else { throw ScriptError("Missing <appcast> path or URL") }
    self.appcast = appcast
  }
}

// MARK: - Commands

func runAppcast(_ options: AppcastOptions, project: Project) async throws {
  let items = try AppcastParser.parse(try await load(options.appcast), source: options.appcast)

  var report: [String] = []
  let liveBuild: Int?
  let liveSource: String?
  switch options.liveFeed {
  case .project: liveSource = project.feedURL.absoluteString
  case .source(let source): liveSource = source
  case .none: liveSource = nil
  }
  if let liveSource {
    let liveItems = try AppcastParser.parse(try await load(liveSource), source: liveSource)
    guard let highest = liveItems.compactMap({ $0.build.flatMap { Int($0) } }).max() else {
      throw ScriptError("Live feed \(liveSource) has no integer sparkle:version")
    }
    liveBuild = highest
    report.append("Live feed \(liveSource) is at build \(highest)")
  } else {
    liveBuild = nil
  }

  let localArchive = try options.archivePath.map {
    (
      name: URL(fileURLWithPath: $0).lastPathComponent,
      data: try Data(contentsOf: URL(fileURLWithPath: $0))
    )
  }

  var failures = 0
  for item in items {
    var archive: Data?
    if let localArchive, localArchive.name == item.archiveName {
      archive = localArchive.data
    } else if options.download, item.edSignature != nil, let url = item.enclosureURL {
      archive = try await fetch(url)
    }
    let found = violations(for: item, archive: archive, liveBuild: liveBuild, project: project)
    if found.isEmpty {
      report.append("ok    \(item.label)")
    } else {
      failures += 1
      report += found.map { "FAIL  \(item.label): \($0)" }
    }
  }

  guard failures == 0 else {
    let summary = "\(failures) of \(items.count) appcast item(s) failed release checks"
    throw ScriptError(([summary] + report).joined(separator: "\n"))
  }
  print(report.joined(separator: "\n"))
}

// MARK: - Entry point

await runAsyncMain {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()), scriptName: cli.scriptName)
  cli.preflight(args)
  guard let mode = args.first else { throw ScriptError("Missing command argument") }
  guard let command = Command(rawValue: mode) else { throw ScriptError("Unknown command: \(mode)") }

  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let project = try Project.load(repoRoot: repoRoot)
  switch command {
  case .minOS: print(project.deploymentTarget)
  case .appcast: try await runAppcast(try AppcastOptions(Array(args.dropFirst())), project: project)
  }
}
