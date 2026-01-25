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
  case buildOnly = "--build-only"
  case buildOnlyShort = "-b"

  static var completions: [String] { allCases.map(\.rawValue) }
}

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

struct Config {
  var verbose: Bool = false
  var buildOnly: Bool = false
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
    case .buildOnly, .buildOnlyShort:
      config.buildOnly = true
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

func killRunningApp() {
  // Kill any running instance of Saga (ignore errors if not running)
  _ = try? runCommand("pkill", ["-x", "Saga"], allowFailure: true, emitOutput: false)
}

func buildApp(projectPath: String, derivedDataPath: String, arch: String, verbose: Bool) throws {
  killRunningApp()
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

func waitForProcessID(named processName: String, retries: Int = 20, delaySeconds: TimeInterval = 0.25)
  throws -> Int
{
  for _ in 0..<retries {
    let output = try runCommand(
      "pgrep",
      ["-x", "-n", processName],
      allowFailure: true,
      emitOutput: false
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if let pid = Int(trimmed) {
      return pid
    }
    Thread.sleep(forTimeInterval: delaySeconds)
  }
  throw ScriptError("Timed out waiting for \(processName) to launch.")
}

func streamLogs(processName: String) throws -> Process {
  let predicate = "process == \"\(processName)\" && subsystem == \"Saga\""
  print("Streaming logs for \(processName). Press Ctrl+C to stop.")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [
    "log", "stream", "--predicate", predicate, "--style", "compact", "--level", "debug",
  ]
  process.standardOutput = FileHandle.standardOutput
  process.standardError = FileHandle.standardError
  try process.run()
  return process
}

func waitForProcessExit(processID: Int) {
  while kill(pid_t(processID), 0) == 0 {
    Thread.sleep(forTimeInterval: 0.5)
  }
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
      if !config.buildOnly {
        let logProcess = try streamLogs(processName: "Saga")
        try openApp(at: appPath)
        let pid = try waitForProcessID(named: "Saga")
        waitForProcessExit(processID: pid)
        logProcess.terminate()
      }
    }
  }
}
