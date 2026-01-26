// DESCRIPTION: Set up shell completions for run

import Common
import Foundation

// MARK: - CLI

let cli = SimpleCLI(
  filePath: #filePath,
  notes: [
    "Only adds completions if not already present",
    "Restart your shell or run 'source ~/.zshrc' to activate",
  ]
)

func parseArguments(_ args: [String]) throws {
  guard args.isEmpty else {
    throw ScriptError("Unknown argument: \(args.joined(separator: " "))")
  }
}

@main
struct BootstrapCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()), scriptName: cli.scriptName)
      cli.preflight(args)
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
