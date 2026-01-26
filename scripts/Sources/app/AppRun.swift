import Common
import Foundation

struct AppPaths {
  let derivedDataPath: String
  let resultBundlePath: String
  let screenshotsPath: String
  let appPath: String

  init(
    repoRoot: String,
    cacheKey: String,
    configuration: String = "Debug",
    appName: String = "Saga"
  ) {
    let buildRoot = URL(fileURLWithPath: repoRoot).appendingPathComponent("build")
    derivedDataPath = buildRoot.appendingPathComponent(cacheKey).path
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
    appPath =
      URL(fileURLWithPath: derivedDataPath)
      .appendingPathComponent("Build/Products/\(configuration)/\(appName).app")
      .path
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
