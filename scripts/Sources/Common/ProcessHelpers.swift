import Foundation

// MARK: - Process and system helpers

/// Ensures the active developer directory points to full Xcode, not CLT.
public func checkXcodeToolsSelected() throws {
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

/// Returns true when the 1Password CLI is authenticated for the account.
public func isOnePasswordAuthenticated(account: String) -> Bool {
  let output = try? runCommand(
    "op",
    ["whoami", "--account", account],
    allowFailure: true,
    emitOutput: false
  )
  return !(output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Signs into 1Password for the given account.
public func signInToOnePassword(account: String) throws {
  _ = try runCommand("op", ["signin", "--account", account])
}

/// Reads a secret from 1Password using the secret reference syntax.
public func readOnePasswordSecret(
  vault: String,
  item: String,
  field: String = "value"
) throws -> String {
  let reference = "op://\(vault)/\(item)/\(field)"
  let value = try runCommand("op", ["read", reference], emitOutput: false)
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw ScriptError("Empty secret returned for \(reference)")
  }
  return trimmed
}

/// Returns the current machine architecture (e.g. arm64, x86_64).
public func currentArchitecture() throws -> String {
  try runCommand("uname", ["-m"], emitOutput: false)
}

/// Terminates a running process by exact name (no-op if not running).
public func terminateProcess(named processName: String) {
  _ = try? runCommand("pkill", ["-x", processName], allowFailure: true, emitOutput: false)
}

/// Opens an app bundle at the given path.
public func openApp(at path: String) throws {
  guard FileManager.default.fileExists(atPath: path) else {
    throw ScriptError("App not found at \(path)")
  }
  try runCommand("open", [path])
}

/// Waits for a process to appear, returning its PID or throwing on timeout.
public func waitForProcessID(
  named processName: String, retries: Int = 20, delaySeconds: TimeInterval = 0.25
)
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

/// Streams unified logs for the named process and subsystem until terminated.
public func streamLogs(processName: String, subsystem: String = "Saga") throws -> Process {
  let predicate = "process == \"\(processName)\" && subsystem == \"\(subsystem)\""
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

/// Blocks until the given PID exits.
public func waitForProcessExit(processID: Int) {
  while kill(pid_t(processID), 0) == 0 {
    Thread.sleep(forTimeInterval: 0.5)
  }
}

/// Installs SIGINT/SIGTERM handlers that run cleanup before exiting.
public func installSignalHandlers(onTerminate: @escaping () -> Void) -> [DispatchSourceSignal] {
  let signals: [Int32] = [SIGINT, SIGTERM]
  var sources: [DispatchSourceSignal] = []
  for signalValue in signals {
    signal(signalValue, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalValue, queue: .global())
    source.setEventHandler {
      onTerminate()
      exit(128 + Int32(signalValue))
    }
    source.resume()
    sources.append(source)
  }
  return sources
}
