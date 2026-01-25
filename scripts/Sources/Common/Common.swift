import Foundation

// MARK: - Shared helpers for scripts in this directory

public struct ScriptError: Error, CustomStringConvertible {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String {
    message
  }
}

// MARK: - Command execution

@discardableResult
public func runCommand(
  _ command: String,
  _ args: [String],
  cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
  allowFailure: Bool = false,
  failOnStderr: Bool = false,
  emitOutput: Bool = true
) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [command] + args
  process.currentDirectoryURL = cwd

  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr

  try process.run()
  process.waitUntilExit()

  let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
  let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
  let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
  let trimmedStdout = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  let trimmedStderr = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)

  if process.terminationStatus != 0 {
    if emitOutput {
      if !stdoutText.isEmpty {
        print(stdoutText, terminator: "")
      }
      if !stderrText.isEmpty {
        FileHandle.standardError.write(stderrData)
      }
    }
    if allowFailure {
      return trimmedStdout
    }
    let message: String
    if trimmedStderr.isEmpty {
      message = "Command failed: \(command) \(args.joined(separator: " "))"
    } else if emitOutput {
      message = trimmedStderr
    } else {
      message = "Command failed: \(command) \(args.joined(separator: " "))\n\(trimmedStderr)"
    }
    throw ScriptError(message)
  }

  if failOnStderr && !trimmedStderr.isEmpty {
    if emitOutput, !stdoutText.isEmpty {
      print(stdoutText, terminator: "")
    }
    throw ScriptError(trimmedStderr)
  }

  if emitOutput {
    if !stdoutText.isEmpty {
      print(stdoutText, terminator: "")
    }
    if !stderrText.isEmpty {
      FileHandle.standardError.write(stderrData)
    }
  }

  return trimmedStdout
}

// MARK: - Git helpers

public func gitRoot(cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
  -> String?
{
  do {
    let output = try runCommand(
      "git", ["rev-parse", "--show-toplevel"],
      cwd: cwd, allowFailure: true, emitOutput: false
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  } catch {
    return nil
  }
}

// MARK: - Argument handling

public func normalizeScriptArgs(_ args: [String], scriptName: String) -> [String] {
  var normalized = args
  if normalized.first == "--" {
    normalized.removeFirst()
  }
  if let first = normalized.first,
    URL(fileURLWithPath: first).lastPathComponent == scriptName
  {
    normalized.removeFirst()
  }
  if normalized.first == "--" {
    normalized.removeFirst()
  }
  return normalized
}

// MARK: - Script description

/// Reads the DESCRIPTION comment from the top of a script's source file.
/// Usage: `scriptDescription(filePath: #filePath)`
public func scriptDescription(filePath: String) -> String {
  guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
    return ""
  }
  for line in content.components(separatedBy: .newlines) {
    if line.hasPrefix("// DESCRIPTION:") {
      return line.replacingOccurrences(of: "// DESCRIPTION:", with: "").trimmingCharacters(
        in: .whitespaces)
    }
  }
  return ""
}

// MARK: - Entry point wrapper

/// Runs a main function with standard error handling.
public func runMain(_ body: () throws -> Void) {
  do {
    try body()
  } catch {
    let message: String
    if let scriptError = error as? ScriptError {
      message = scriptError.description
    } else {
      message = error.localizedDescription
    }
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
  }
}

/// Runs a main function with usage text shown on error.
public func runMain(usage: @autoclosure () -> String, _ body: () throws -> Void) {
  do {
    try body()
  } catch {
    let usageText = usage()
    let errorText: String
    if let scriptError = error as? ScriptError {
      errorText = scriptError.description
    } else {
      errorText = error.localizedDescription
    }
    FileHandle.standardError.write(Data("\(usageText)\nError: \(errorText)\n".utf8))
    exit(1)
  }
}
