// DESCRIPTION: Run Swift format and/or lint checks

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

/// Directories to check (relative to repo root). Excludes build/, .build/, etc.
let targetDirectories = ["Saga", "scripts"]

// MARK: - CLI

enum Option: String, CaseIterable {
  case help = "--help"
  case helpShort = "-h"
  case format = "--format"
  case lint = "--lint"

  static var completions: [String] { allCases.map(\.rawValue) }
}

struct ChecksSelection {
  var runFormat: Bool
  var runLint: Bool
}

func usage() -> String {
  """
  \(description)

  Usage:
    run checks [--format] [--lint]

  Options:
    --format    Run formatting checks only
    --lint      Run lint checks only

  Notes:
    - Uses swift-format with repo config (.swift-format)
    - Defaults to running both format and lint when no options are provided
    - Checks only: \(targetDirectories.joined(separator: ", "))
  """
}

func parseArguments(_ args: [String]) throws -> ChecksSelection {
  var runFormat = false
  var runLint = false

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
struct ChecksCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(Array(CommandLine.arguments.dropFirst()), scriptName: "checks")
      let selection = try parseArguments(args)

      let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
      let repoURL = URL(fileURLWithPath: repoRoot)
      guard FileManager.default.fileExists(atPath: repoRoot) else {
        throw ScriptError("Path does not exist: \(repoRoot)")
      }

      let configPath = findConfigurationPath(repoRoot: repoRoot)

      for directory in targetDirectories {
        let targetPath = repoURL.appendingPathComponent(directory).path
        guard FileManager.default.fileExists(atPath: targetPath) else {
          continue
        }
        if selection.runFormat {
          try runSwiftFormat(
            subcommand: "format",
            targetPath: targetPath,
            configPath: configPath,
            extraArgs: ["--in-place"],
            cwd: repoURL,
            description: "Formatting \(directory)/..."
          )
        }
        if selection.runLint {
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
}
