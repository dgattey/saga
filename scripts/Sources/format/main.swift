// DESCRIPTION: Format and lint all Swift files

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

/// Directories to format (relative to repo root). Excludes build/, .build/, etc.
let targetDirectories = ["Saga", "scripts"]

// MARK: - CLI

enum Option: String, CaseIterable {
  case help = "--help"
  case helpShort = "-h"

  static var completions: [String] { allCases.map(\.rawValue) }
}

func usage() -> String {
  """
  \(description)

  Usage:
    run format

  Notes:
    - Uses swift-format with repo config (.swift-format)
    - Formats in place, then lints (strict)
    - Only formats: \(targetDirectories.joined(separator: ", "))
  """
}

func parseArguments(_ args: [String]) throws {
  for arg in args {
    if arg == "--completions" {
      print(Option.completions.joined(separator: "\n"))
      exit(0)
    }
    guard let option = Option(rawValue: arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .help, .helpShort:
      print(usage())
      exit(0)
    }
  }
}

func findConfigurationPath(repoRoot: String) -> String? {
  let path = URL(fileURLWithPath: repoRoot).appendingPathComponent(".swift-format").path
  return FileManager.default.fileExists(atPath: path) ? path : nil
}

func findSwiftFormat() -> (command: String, args: [String]) {
  // Check if swift-format is in PATH (e.g., installed via Homebrew)
  let whichResult = try? runCommand("which", ["swift-format"], emitOutput: false)
  if let path = whichResult, !path.isEmpty {
    return ("swift-format", [])
  }
  // Fall back to xcrun (e.g., bundled with Xcode)
  return ("xcrun", ["swift-format"])
}

func runSwiftFormat(
  subcommand: String,
  targetPath: String,
  configPath: String?,
  extraArgs: [String],
  cwd: URL,
  description: String
) throws {
  print(description)
  let (command, commandPrefix) = findSwiftFormat()
  var args = commandPrefix + [subcommand, "--recursive", "--parallel"]
  if let configPath { args.append(contentsOf: ["--configuration", configPath]) }
  args.append(contentsOf: extraArgs)
  args.append(targetPath)
  try runCommand(command, args, cwd: cwd, failOnStderr: true)
}

@main
struct FormatCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(Array(CommandLine.arguments.dropFirst()), scriptName: "format")
      try parseArguments(args)

      let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
      let repoURL = URL(fileURLWithPath: repoRoot)
      guard FileManager.default.fileExists(atPath: repoRoot) else {
        throw ScriptError("Path does not exist: \(repoRoot)")
      }

      let configPath = findConfigurationPath(repoRoot: repoRoot)

      // Format and lint each target directory (excludes build folders)
      for directory in targetDirectories {
        let targetPath = repoURL.appendingPathComponent(directory).path
        guard FileManager.default.fileExists(atPath: targetPath) else {
          continue
        }
        try runSwiftFormat(
          subcommand: "format",
          targetPath: targetPath,
          configPath: configPath,
          extraArgs: ["--in-place"],
          cwd: repoURL,
          description: "Formatting \(directory)/..."
        )
        try runSwiftFormat(
          subcommand: "lint",
          targetPath: targetPath,
          configPath: configPath,
          extraArgs: ["--strict"],
          cwd: repoURL,
          description: "Linting \(directory)/..."
        )
      }
    }
  }
}
