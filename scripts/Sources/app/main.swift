// DESCRIPTION: Build and launch the app

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case verbose
  case buildOnly = "build-only"
  case uiTest = "ui-test"

  var shortName: String? {
    switch self {
    case .verbose: "v"
    case .buildOnly: "b"
    case .uiTest: nil
    }
  }

  var description: String {
    switch self {
    case .verbose: "Show full xcodebuild output (default is quiet)"
    case .buildOnly: "Build without launching the app"
    case .uiTest: "Run XCUITest UI tests and capture screenshots"
    }
  }
}

struct Config {
  var verbose = false
  var buildOnly = false
  var runUiTests = false
}

func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()

  for arg in args {
    guard let option = Option.match(arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .verbose:
      config.verbose = true
    case .buildOnly:
      config.buildOnly = true
    case .uiTest:
      config.runUiTests = true
    }
  }

  if config.runUiTests, config.buildOnly {
    throw ScriptError("--build-only is not supported with --ui-test")
  }

  return config
}

// MARK: - Main

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  notes: ["When launching the app, this command streams logs until you stop it."]
)

runMain(usage: cli.usage()) {
  let args = normalizeScriptArgs(
    Array(CommandLine.arguments.dropFirst()),
    scriptName: cli.scriptName
  )
  cli.preflight(args)
  let config = try parseArguments(args)

  let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
  let projectPath = try findProjectPath(repoRoot: repoRoot)
  let cacheKey = buildCacheKey(repoRoot: repoRoot)
  let paths = AppPaths(repoRoot: repoRoot, cacheKey: cacheKey)

  try checkXcodeToolsSelected()
  let arch = try currentArchitecture()
  if config.runUiTests {
    try runUiTests(
      projectPath: projectPath,
      derivedDataPath: paths.derivedDataPath,
      arch: arch,
      verbose: config.verbose,
      resultBundlePath: paths.resultBundlePath,
      screenshotsPath: paths.screenshotsPath
    )
  } else {
    try buildApp(
      projectPath: projectPath,
      derivedDataPath: paths.derivedDataPath,
      arch: arch,
      verbose: config.verbose
    )
    if !config.buildOnly {
      try runApp(appPath: paths.appPath)
    }
  }
}
