import Common
import Foundation

struct AppPaths {
  let resultBundlePath: String
  let screenshotsPath: String

  /// Standard Xcode DerivedData location (for hot reload compatibility)
  static let xcodeDerivedData = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"

  private let configuration: String
  private let appName: String

  /// Computed property to resolve the app path after the build completes.
  /// This must be accessed after `buildApp` runs so the DerivedData folder exists.
  var appPath: String {
    let derivedDataPath = Self.findDerivedData(projectName: appName)
    return URL(fileURLWithPath: derivedDataPath)
      .appendingPathComponent("Build/Products/\(configuration)/\(appName).app")
      .path
  }

  init(
    repoRoot: String,
    cacheKey: String,
    configuration: String = "Debug",
    appName: String = "Saga"
  ) {
    self.configuration = configuration
    self.appName = appName

    let buildRoot = URL(fileURLWithPath: repoRoot).appendingPathComponent("build")

    resultBundlePath =
      buildRoot
      .appendingPathComponent("UITestResults")
      .appendingPathComponent("\(cacheKey).xcresult")
      .path
    screenshotsPath =
      buildRoot
      .appendingPathComponent("UITestScreenshots")
      .appendingPathComponent(cacheKey)
      .path
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

func runApp(appPath: String, processName: String = "Saga", subsystem: String = "Saga") throws {
  terminateProcess(named: processName)
  try waitForProcessToExit(named: processName)
  print("Streaming logs for \(processName). Press Ctrl+C to stop.")
  let logProcess = try streamLogs(processName: processName, subsystem: subsystem)
  let signalSources = installSignalHandlers {
    logProcess.terminate()
  }
  defer { _ = signalSources }

  print("Launching \(processName)...")
  try openApp(at: appPath)
  let pid = try waitForProcessID(named: processName)
  waitForProcessExit(processID: pid)
  logProcess.terminate()
}

func waitForProcessToExit(
  named processName: String, retries: Int = 20, delaySeconds: TimeInterval = 0.25
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
