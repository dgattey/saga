// DESCRIPTION: Remove build artifacts and SwiftPM build caches

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case all
  case dryRun = "dry-run"

  var shortName: String? {
    switch self {
    case .all: "a"
    case .dryRun: "n"
    }
  }

  var description: String {
    switch self {
    case .all: "Also remove SwiftPM's .build/ (compiled products and resolved packages)"
    case .dryRun: "Show what would be deleted without deleting"
    }
  }
}

struct Config {
  var includeSwiftPMBuild = false
  var dryRun = false
}

func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()

  for arg in args {
    guard let option = Option.match(arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .all:
      config.includeSwiftPMBuild = true
    case .dryRun:
      config.dryRun = true
    }
  }

  return config
}

// MARK: - Clean Functions

func removeDirectory(at path: String, dryRun: Bool) {
  let fileManager = FileManager.default
  guard fileManager.fileExists(atPath: path) else {
    print("  (not found) \(path)")
    return
  }

  if dryRun {
    print("  Would remove: \(path)")
  } else {
    do {
      try fileManager.removeItem(atPath: path)
      print("  Removed: \(path)")
    } catch {
      print("  Failed to remove \(path): \(error.localizedDescription)")
    }
  }
}

// MARK: - Main

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  notes: ["Removes build/ and dist/, and optionally SwiftPM's .build/."]
)

runMain(usage: cli.usage()) {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()),
    scriptName: cli.scriptName
  )
  cli.preflight(args)
  let config = try parseArguments(args)

  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let root = URL(fileURLWithPath: repoRoot)

  if config.dryRun {
    print("Dry run - showing what would be cleaned:\n")
  } else {
    print("Cleaning build artifacts...\n")
  }

  var directories = ["build", "dist"]
  if config.includeSwiftPMBuild {
    directories.append(".build")
  }
  for directory in directories {
    removeDirectory(at: root.appendingPathComponent(directory).path, dryRun: config.dryRun)
  }

  print("\nDone!")
}
