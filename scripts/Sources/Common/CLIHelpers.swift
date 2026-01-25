import Foundation

// MARK: - CLI helpers

/// Handles standard CLI flags like --help/-h and --completions.
public func preflightCLI(
  _ args: [String],
  completions: [String],
  usage: @autoclosure () -> String
) {
  if args.contains("--completions") {
    print(completions.joined(separator: "\n"))
    exit(0)
  }
  if args.contains("--help") || args.contains("-h") {
    print(usage())
    exit(0)
  }
}

/// Combines script-specific completions with standard CLI flags.
public func standardCompletions(_ completions: [String]) -> [String] {
  let standard = ["--help", "-h", "--completions"]
  var combined = completions
  for option in standard where !combined.contains(option) {
    combined.append(option)
  }
  return combined
}
