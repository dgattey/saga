// DESCRIPTION: Remove build artifacts and derived data

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
    case .all: "Also remove Xcode's global DerivedData for this project"
    case .dryRun: "Show what would be deleted without deleting"
    }
  }
}

struct Config {
  var includeGlobalDerivedData = false
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
      config.includeGlobalDerivedData = true
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

func findXcodeDerivedData(projectName: String) -> [String] {
  let derivedDataPath =
    NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
  let fileManager = FileManager.default

  guard let contents = try? fileManager.contentsOfDirectory(atPath: derivedDataPath) else {
    return []
  }

  return
    contents
    .filter { $0.hasPrefix("\(projectName)-") }
    .map { "\(derivedDataPath)/\($0)" }
}

// MARK: - Main

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  notes: ["Removes the build/ directory and optionally Xcode's DerivedData."]
)

runMain(usage: cli.usage()) {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()),
    scriptName: cli.scriptName
  )
  cli.preflight(args)
  let config = try parseArguments(args)

  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let buildPath = URL(fileURLWithPath: repoRoot).appendingPathComponent("build").path

  if config.dryRun {
    print("Dry run - showing what would be cleaned:\n")
  } else {
    print("Cleaning build artifacts...\n")
  }

  // Always clean local build directory
  print("Local build directory:")
  removeDirectory(at: buildPath, dryRun: config.dryRun)

  // Optionally clean Xcode's global DerivedData
  if config.includeGlobalDerivedData {
    print("\nXcode DerivedData:")
    let derivedDataDirs = findXcodeDerivedData(projectName: "Saga")
    if derivedDataDirs.isEmpty {
      print("  (no Saga DerivedData found)")
    } else {
      for dir in derivedDataDirs {
        removeDirectory(at: dir, dryRun: config.dryRun)
      }
    }
  }

  print("\nDone!")
}
