// DESCRIPTION: Build and launch the app

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case buildOnly = "build-only"
  case release
  case background
  case foreground
  case test

  var shortName: String? {
    switch self {
    case .buildOnly: "b"
    case .release: "r"
    case .background: "g"
    case .foreground: "f"
    case .test: "t"
    }
  }

  var description: String {
    switch self {
    case .buildOnly: "Build build/Saga.app without launching it"
    case .release: "Build and/or run in release configuration (default is debug)"
    case .background: "Launch in background without stealing focus (open -g -j) and exit"
    case .foreground: "Bring the app to the foreground when launching"
    case .test: "Run unit tests (SagaTests) with swift test"
    }
  }
}

struct Config {
  var buildOnly = false
  var release = false
  var background = false
  var foreground = false
  var runUnitTests = false

  /// Avoid stealing focus unless `--foreground` is explicitly requested.
  var shouldOpenInBackground: Bool {
    !foreground
  }

  /// Exit once the app is running instead of blocking on `log stream` when `--background` is set
  /// or when running in a non-interactive / automated agent shell.
  var shouldStreamLogs: Bool {
    if background {
      return false
    }
    let env = ProcessInfo.processInfo.environment
    if env["CURSOR_AGENT"] != nil || env["CURSOR_TRACE_ID"] != nil || env["CI"] != nil {
      return false
    }
    return isatty(STDIN_FILENO) != 0
  }
}

func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()

  for arg in args {
    guard let option = Option.match(arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .buildOnly:
      config.buildOnly = true
    case .release:
      config.release = true
    case .background:
      config.background = true
    case .foreground:
      config.foreground = true
    case .test:
      config.runUnitTests = true
    }
  }

  if config.background, config.foreground {
    throw ScriptError("--background and --foreground cannot be used together")
  }

  if config.runUnitTests, config.buildOnly {
    throw ScriptError("--build-only is not supported with --test")
  }

  if config.runUnitTests, config.release {
    throw ScriptError("--release is not supported with --test")
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
  try checkXcodeToolsSelected()
  if config.runUnitTests {
    try runUnitTests(repoRoot: repoRoot)
    return
  }
  let appPath = try buildApp(repoRoot: repoRoot, release: config.release)
  if !config.buildOnly {
    try runApp(
      appPath: appPath,
      background: config.shouldOpenInBackground,
      streamLogsUntilExit: config.shouldStreamLogs
    )
  }
}
