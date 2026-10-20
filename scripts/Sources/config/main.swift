// DESCRIPTION: Write Saga/Saga/Config/Config.xcconfig

import Common
import Foundation

// MARK: - CLI

let cli = SimpleCLI(
  filePath: #filePath,
  examples: ["run config"],
  notes: [
    "Reads \(AppConfig.spaceIDKey) and \(AppConfig.accessTokenKey) (plus optional \(AppConfig.sagaAPISecretKey)) from the environment",
    "Builds without this file still compile; scripts/build-macos.sh falls back to placeholder credentials",
    "Use 'run bootstrap' to pull real credentials from 1Password",
  ]
)

// MARK: - Main

runMain(usage: cli.usage()) {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()),
    scriptName: cli.scriptName
  )
  cli.preflight(args)
  if let unknown = args.first {
    throw ScriptError("Unknown argument: \(unknown)")
  }

  guard let values = AppConfig.valuesFromEnvironment() else {
    throw ScriptError(
      """
      Set \(AppConfig.spaceIDKey) and \(AppConfig.accessTokenKey). \
      'run bootstrap' pulls real values from 1Password.
      """
    )
  }
  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  try AppConfig.write(repoRoot: repoRoot, values: values)
  print("Wrote \(AppConfig.displayPath(repoRoot: repoRoot)) from the environment")
}
