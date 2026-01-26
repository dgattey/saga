// DESCRIPTION: Build and launch the app

import Common
import Foundation

// MARK: - CLI

enum Option: String, CLIOptionType, CaseIterable {
  case verbose
  case buildOnly = "build-only"

  var shortName: String? {
    switch self {
    case .verbose: "v"
    case .buildOnly: "b"
    }
  }

  var description: String {
    switch self {
    case .verbose: "Show full xcodebuild output (default is quiet)"
    case .buildOnly: "Build without launching the app"
    }
  }
}

let cli = CLI(
  filePath: #filePath,
  options: Option.self,
  notes: ["When launching the app, this command streams logs until you stop it."]
)

/// Parsed configuration for the app command.
struct Config {
  var verbose = false
  var buildOnly = false
}

/// Parses CLI arguments into a config.
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
    }
  }

  return config
}

// MARK: - Build helpers

/// Builds the Saga macOS app using xcodebuild.
func buildApp(projectPath: String, derivedDataPath: String, arch: String, verbose: Bool) throws {
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
    runMain(usage: cli.usage()) {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()), scriptName: cli.scriptName)
      cli.preflight(args)
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
        terminateProcess(named: "Saga")
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
