// DESCRIPTION: Write Saga/Saga/Config/Config.xcconfig

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case placeholder
  case ifMissing = "if-missing"

  var description: String {
    switch self {
    case .placeholder: "Write placeholder credentials instead of reading the environment"
    case .ifMissing: "Do nothing if Config.xcconfig already exists"
    }
  }
}

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  examples: [
    "run config",
    "run config --placeholder --if-missing",
  ],
  notes: [
    "Reads \(AppConfig.spaceIDKey) and \(AppConfig.accessTokenKey) from the environment",
    "Use --placeholder for build-only environments; compiling never contacts Contentful",
    "Use 'run bootstrap' to pull real credentials from 1Password",
  ]
)

struct Selection {
  var usePlaceholder = false
  var skipIfPresent = false
}

func parseArguments(_ args: [String]) throws -> Selection {
  var selection = Selection()
  for arg in args {
    guard let option = Option.match(arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .placeholder:
      selection.usePlaceholder = true
    case .ifMissing:
      selection.skipIfPresent = true
    }
  }
  return selection
}

// MARK: - Main

runMain(usage: cli.usage()) {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()),
    scriptName: cli.scriptName
  )
  cli.preflight(args)
  let selection = try parseArguments(args)

  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let displayPath = AppConfig.displayPath(repoRoot: repoRoot)

  if selection.skipIfPresent, AppConfig.exists(repoRoot: repoRoot) {
    print("\(displayPath) already exists, leaving it alone")
    return
  }

  let values: AppConfigValues
  if selection.usePlaceholder {
    values = AppConfig.placeholderValues
  } else {
    guard let environmentValues = AppConfig.valuesFromEnvironment() else {
      throw ScriptError(
        """
        Set \(AppConfig.spaceIDKey) and \(AppConfig.accessTokenKey), or pass --placeholder \
        to write build-only stand-ins. 'run bootstrap' pulls real values from 1Password.
        """
      )
    }
    values = environmentValues
  }

  try AppConfig.write(repoRoot: repoRoot, values: values)
  let source = selection.usePlaceholder ? "placeholder values" : "the environment"
  print("Wrote \(displayPath) from \(source)")
}
