// DESCRIPTION: Set up shell completions for run

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

// MARK: - CLI

enum Option: String, CaseIterable {
  case help = "--help"
  case helpShort = "-h"

  static var completions: [String] { allCases.map(\.rawValue) }
}

func usage() -> String {
  """
  \(description)

  Usage:
    run bootstrap

  Notes:
    - Only adds completions if not already present
    - Restart your shell or run 'source ~/.zshrc' to activate
  """
}

func parseArguments(_ args: [String]) throws {
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
    }
  }
}

@main
struct BootstrapCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()), scriptName: "bootstrap")
      try parseArguments(args)

      let repoRoot = gitRoot() ?? FileManager.default.currentDirectoryPath
      let completionsPath = URL(fileURLWithPath: repoRoot)
        .appendingPathComponent("scripts")
        .appendingPathComponent("completions.zsh")
        .path

      let zshrcPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zshrc")
        .path

      print("Setting up Saga development environment...")

      // Check if completions are already configured
      let zshrcExists = FileManager.default.fileExists(atPath: zshrcPath)
      var zshrcContent = ""
      if zshrcExists {
        zshrcContent = try String(contentsOfFile: zshrcPath, encoding: .utf8)
      }

      if zshrcContent.contains(completionsPath) {
        print("Completions already configured in \(zshrcPath)")
      } else {
        // Append completions source line
        let sourceLine = "\n# Saga repo script completions\nsource \"\(completionsPath)\"\n"
        let newContent = zshrcContent + sourceLine
        try newContent.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
        print("Added completions to \(zshrcPath)")
      }

      print("")
      print("Done! Restart your shell or run: source ~/.zshrc")
      print("")
      print("Tab completion examples:")
      print("  run <TAB>          - list scripts")
      print("  run format --<TAB> - list script options")
    }
  }
}
