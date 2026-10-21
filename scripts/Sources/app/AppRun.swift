import Common
import Foundation

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
