import Common
import Foundation

struct AppPaths {
  let derivedDataPath: String
  let appPath: String

  /// Standard Xcode DerivedData location (for hot reload compatibility)
  static let xcodeDerivedData = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"

  init(
    configuration: String = "Debug",
    appName: String = "Saga"
  ) {
    derivedDataPath = Self.findDerivedData(projectName: appName)
    appPath =
      URL(fileURLWithPath: derivedDataPath)
      .appendingPathComponent("Build/Products/\(configuration)/\(appName).app")
      .path
  }

  static func uiTestPaths(repoRoot: String, cacheKey: String) -> (
    resultBundlePath: String, screenshotsPath: String
  ) {
    let buildRoot = URL(fileURLWithPath: repoRoot).appendingPathComponent("build")
    let resultBundlePath =
      buildRoot
      .appendingPathComponent("UITestResults")
      .appendingPathComponent("\(cacheKey).xcresult")
      .path
    let screenshotsPath =
      buildRoot
      .appendingPathComponent("UITestScreenshots")
      .appendingPathComponent(cacheKey)
      .path
    return (resultBundlePath, screenshotsPath)
  }

  static func findDerivedData(projectName: String) -> String {
    let fileManager = FileManager.default
    if let contents = try? fileManager.contentsOfDirectory(atPath: xcodeDerivedData) {
      if let match = contents.first(where: { $0.hasPrefix("\(projectName)-") }) {
        return "\(xcodeDerivedData)/\(match)"
      }
    }
    // Return expected path even if it doesn't exist yet
    return "\(xcodeDerivedData)/\(projectName)"
  }
}

func runApp(
  appPath: String,
  processName: String = "Saga",
  subsystem: String = "Saga",
  background: Bool = true,
  streamLogsUntilExit: Bool = true
) throws {
  if terminateProcess(named: processName) {
    try waitForProcessToExit(named: processName)
  }

  guard streamLogsUntilExit else {
    print("Launching \(processName) in background...")
    try openApp(at: appPath, background: background)
    let pid = try waitForProcessID(named: processName)
    print("Launched \(processName) (PID \(pid)).")
    return
  }

  print("Streaming logs for \(processName). Press Ctrl+C to stop.")
  let logProcess = try streamLogs(processName: processName, subsystem: subsystem)
  let signalSources = installSignalHandlers {
    logProcess.terminate()
  }
  defer { _ = signalSources }

  print("Launching \(processName)...")
  try openApp(at: appPath, background: background)
  let pid = try waitForProcessID(named: processName)
  waitForProcessExit(processID: pid)
  logProcess.terminate()
}

func waitForProcessToExit(
  named processName: String, retries: Int = 100, delaySeconds: TimeInterval = 0.05
)
  throws
{
  for _ in 0..<retries {
    let output = try runCommand(
      "pgrep",
      ["-x", "-n", processName],
      allowFailure: true,
      emitOutput: false
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return
    }
    Thread.sleep(forTimeInterval: delaySeconds)
  }
  throw ScriptError("Timed out waiting for \(processName) to exit.")
}
