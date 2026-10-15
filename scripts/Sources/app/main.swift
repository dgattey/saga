// DESCRIPTION: Build and launch the app

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case verbose
  case buildOnly = "build-only"
  case release
  case uiTest = "ui-test"
  case skipSigning = "skip-signing"

  var shortName: String? {
    switch self {
    case .verbose: "v"
    case .buildOnly: "b"
    case .release: "r"
    case .uiTest: nil
    case .skipSigning: nil
    }
  }

  var description: String {
    switch self {
    case .verbose: "Show full xcodebuild output (default is quiet)"
    case .buildOnly: "Build without launching the app"
    case .release: "Build and/or run in Release configuration (default is Debug)"
    case .uiTest: "Run XCUITest UI tests and capture screenshots"
    case .skipSigning: "Skip code signing (for CI without certificates)"
    }
  }
}

struct Config {
  var verbose = false
  var buildOnly = false
  var release = false
  var runUiTests = false
  var skipSigning = false

  var configuration: String {
    release ? "Release" : "Debug"
  }
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
    case .release:
      config.release = true
    case .uiTest:
      config.runUiTests = true
    case .skipSigning:
      config.skipSigning = true
    }
  }

  if config.runUiTests, config.buildOnly {
    throw ScriptError("--build-only is not supported with --ui-test")
  }

  if config.runUiTests, config.release {
    throw ScriptError("--release is not supported with --ui-test")
  }

  if config.runUiTests, config.skipSigning {
    throw ScriptError("--skip-signing is not supported with --ui-test")
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
  let paths = AppPaths(configuration: config.configuration)

  try checkXcodeToolsSelected()
  let arch = try currentArchitecture()
  if config.runUiTests {
    let cacheKey = buildCacheKey(repoRoot: repoRoot)
    let uiTestPaths = AppPaths.uiTestPaths(repoRoot: repoRoot, cacheKey: cacheKey)
    try runUiTests(
      projectPath: projectPath,
      derivedDataPath: paths.derivedDataPath,
      arch: arch,
      verbose: config.verbose,
      resultBundlePath: uiTestPaths.resultBundlePath,
      screenshotsPath: uiTestPaths.screenshotsPath
    )
  } else {
    try buildApp(
      projectPath: projectPath,
      derivedDataPath: paths.derivedDataPath,
      arch: arch,
      configuration: config.configuration,
      verbose: config.verbose,
      skipSigning: config.skipSigning
    )
    if !config.buildOnly {
      // Re-resolve DerivedData in case this was the very first build
      let resolvedPaths = AppPaths(configuration: config.configuration)
      try runApp(appPath: resolvedPaths.appPath)
    }
  }
}
