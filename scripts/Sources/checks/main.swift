// DESCRIPTION: Run Swift format and/or lint checks

import Common
import Foundation

/// Paths to check (relative to repo root). Excludes build/, scripts/.build/, etc.
let targetPaths = ["Package.swift", "Saga", "scripts/Sources", "scripts/Package.swift"]

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case format
  case lint

  var description: String {
    switch self {
    case .format: "Run formatting checks only"
    case .lint: "Run lint checks only"
    }
  }
}

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  notes: [
    "Uses swift-format with repo config (.swift-format)",
    "Defaults to running both format and lint when no options are provided",
    "Checks only: \(targetPaths.joined(separator: ", "))",
  ]
)

struct ChecksSelection {
  var runFormat: Bool
  var runLint: Bool
}

func parseArguments(_ args: [String]) throws -> ChecksSelection {
  var runFormat = false
  var runLint = false

  for arg in args {
    guard let option = Option.match(arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .format:
      runFormat = true
    case .lint:
      runLint = true
    }
  }

  if !runFormat && !runLint {
    runFormat = true
    runLint = true
  }

  return ChecksSelection(runFormat: runFormat, runLint: runLint)
}

func findConfigurationPath(repoRoot: String) -> String? {
  let path = URL(fileURLWithPath: repoRoot).appendingPathComponent(".swift-format").path
  return FileManager.default.fileExists(atPath: path) ? path : nil
}

func findSwiftFormat() -> (command: String, args: [String]) {
  let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
  let searchDirs =
    envPath.split(separator: ":").map(String.init) + [
      "/opt/homebrew/bin",
      "/usr/local/bin",
    ]
  for dir in searchDirs where !dir.isEmpty {
    let candidate = URL(fileURLWithPath: dir).appendingPathComponent("swift-format").path
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return (candidate, [])
    }
  }
  // Fall back to xcrun (e.g., bundled with Xcode)
  return ("xcrun", ["swift-format"])
}

func runSwiftFormat(
  tool: (command: String, args: [String]),
  subcommand: String,
  targetPaths: [String],
  configPath: String?,
  extraArgs: [String],
  cwd: URL,
  description: String
) throws {
  print(description)
  var args = tool.args + [subcommand, "--recursive", "--parallel"]
  if let configPath { args.append(contentsOf: ["--configuration", configPath]) }
  args.append(contentsOf: extraArgs)
  args.append(contentsOf: targetPaths)
  try runCommand(tool.command, args, cwd: cwd, failOnStderr: true)
}

@main
struct ChecksCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()), scriptName: cli.scriptName)
      cli.preflight(args)
      let selection = try parseArguments(args)

      let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
      let repoURL = URL(fileURLWithPath: repoRoot)
      guard FileManager.default.fileExists(atPath: repoRoot) else {
        throw ScriptError("Path does not exist: \(repoRoot)")
      }

      let configPath = findConfigurationPath(repoRoot: repoRoot)
      let existingTargets = targetPaths.compactMap {
        relativePath -> (label: String, path: String)? in
        let fullPath = repoURL.appendingPathComponent(relativePath).path
        return FileManager.default.fileExists(atPath: fullPath) ? (relativePath, fullPath) : nil
      }
      guard !existingTargets.isEmpty else { return }

      let tool = findSwiftFormat()
      let labels = existingTargets.map(\.label).joined(separator: ", ")
      let paths = existingTargets.map(\.path)

      if selection.runFormat {
        try runSwiftFormat(
          tool: tool,
          subcommand: "format",
          targetPaths: paths,
          configPath: configPath,
          extraArgs: ["--in-place"],
          cwd: repoURL,
          description: "Formatting \(labels)..."
        )
      }
      if selection.runLint {
        try runSwiftFormat(
          tool: tool,
          subcommand: "lint",
          targetPaths: paths,
          configPath: configPath,
          extraArgs: ["--strict"],
          cwd: repoURL,
          description: "Linting \(labels)..."
        )

        let webIconsCheck = repoURL.appendingPathComponent("scripts/sync-web-icons.sh").path
        if FileManager.default.isExecutableFile(atPath: webIconsCheck) {
          print("Verifying server/ web icons and preview assets...")
          try runCommand(webIconsCheck, ["--check"], cwd: repoURL)
        }
      }
    }
  }
}
