// DESCRIPTION: Build and launch the app

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

// MARK: - CLI

enum Option: String, CaseIterable {
  case help = "--help"
  case helpShort = "-h"
  case verbose = "--verbose"
  case verboseShort = "-v"

  static var completions: [String] { allCases.map(\.rawValue) }
}

func usage() -> String {
  """
  \(description)

  Usage:
    run app [--verbose|-v]

  Options:
    --verbose, -v    Show full xcodebuild output (default is quiet)
    --help, -h       Show this help message
  """
}

struct Config {
  var verbose: Bool = false
}

func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()

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
    case .verbose, .verboseShort:
      config.verbose = true
    }
  }

  return config
}

// MARK: - Build helpers

func findProjectPath(repoRoot: String) throws -> String {
  let path = URL(fileURLWithPath: repoRoot)
    .appendingPathComponent("Saga")
    .appendingPathComponent("Saga.xcodeproj")
    .path
  guard FileManager.default.fileExists(atPath: path) else {
    throw ScriptError("Xcode project not found at \(path)")
  }
  return path
}

func checkXcodeToolsSelected() throws {
  let output = try runCommand(
    "xcode-select", ["-p"],
    allowFailure: true,
    emitOutput: false
  )
  if output == "/Library/Developer/CommandLineTools" {
    throw ScriptError(
      """
      Xcode build tools are not selected.
      Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
      """
    )
  }
}

func currentArchitecture() throws -> String {
  try runCommand("uname", ["-m"], emitOutput: false)
}

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

func openApp(at path: String) throws {
  guard FileManager.default.fileExists(atPath: path) else {
    throw ScriptError("App not found at \(path)")
  }
  print("Launching Saga...")
  try runCommand("open", [path])
}

// MARK: - Main

@main
struct AppCommand {
  static func main() {
    runMain(usage: usage()) {
      let args = normalizeScriptArgs(Array(CommandLine.arguments.dropFirst()), scriptName: "app")
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
      try openApp(at: appPath)
    }
  }
}
