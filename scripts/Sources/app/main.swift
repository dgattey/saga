// DESCRIPTION: Build and launch the app

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

// MARK: - CLI

/// CLI options supported by the app runner.
enum Option: String, CaseIterable {
  case verbose = "--verbose"
  case verboseShort = "-v"
  case buildOnly = "--build-only"
  case buildOnlyShort = "-b"

  static var completions: [String] { allCases.map(\.rawValue) }
}

/// Returns the help/usage text for this command.
func usage() -> String {
  """
  \(description)

  Usage:
    run app [--verbose|-v] [--build-only|-b]

  Options:
    --verbose, -v      Show full xcodebuild output (default is quiet)
    --build-only, -b   Build without launching the app
    --help, -h         Show this help message

  Notes:
    When launching the app, this command streams logs until you stop it.
  """
}

/// Parsed configuration for the app command.
struct Config {
  var verbose: Bool = false
  var buildOnly: Bool = false
}

/// Parses CLI arguments into a config, exiting on help/completions.
func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()

  for arg in args {
    guard let option = Option(rawValue: arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .verbose, .verboseShort:
      config.verbose = true
    case .buildOnly, .buildOnlyShort:
      config.buildOnly = true
    }
  }

  return config
}

// MARK: - Build helpers

/// Builds the Saga macOS app using xcodebuild.
func buildApp(projectPath: String, derivedDataPath: String, arch: String, verbose: Bool) throws {
  terminateProcess(named: "Saga")
  print("Building Saga (Debug)...")
  var args = [
    "-project", projectPath,
    "-scheme", "Saga",
    "-configuration", "Debug",
    "-destination", "platform=macOS,arch=\(arch)",
    "-derivedDataPath", derivedDataPath,
    "build",
  ]
  if !verbose {
    args.insert("-quiet", at: 0)
  }
  try runCommand("xcodebuild", args)
}

// MARK: - Main

/// Entry point for `run app`.
@main
struct AppCommand {
  static func main() {
    runMain(usage: usage()) {
      let args = normalizeScriptArgs(Array(CommandLine.arguments.dropFirst()), scriptName: "app")
      preflightCLI(args, completions: standardCompletions(Option.completions), usage: usage())
      let config = try parseArguments(args)

      let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
      let projectPath = try findProjectPath(repoRoot: repoRoot)
      let derivedDataPath = URL(fileURLWithPath: repoRoot).appendingPathComponent("build").path
      let appPath = URL(fileURLWithPath: derivedDataPath)
        .appendingPathComponent("Build/Products/Debug/Saga.app")
        .path

      try checkXcodeToolsSelected()
      let arch = try currentArchitecture()
      try buildApp(
        projectPath: projectPath,
        derivedDataPath: derivedDataPath,
        arch: arch,
        verbose: config.verbose
      )
      if !config.buildOnly {
        var logProcess: Process?
        let signalSources = installSignalHandlers {
          logProcess?.terminate()
        }
        _ = signalSources
        print("Streaming logs for Saga. Press Ctrl+C to stop.")
        logProcess = try streamLogs(processName: "Saga")
        print("Launching Saga...")
        try openApp(at: appPath)
        let pid = try waitForProcessID(named: "Saga")
        waitForProcessExit(processID: pid)
        logProcess?.terminate()
      }
    }
  }
}
