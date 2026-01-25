// DESCRIPTION: Drop version bump commits on branch and rebase onto main

import Common
import Foundation

let description = scriptDescription(filePath: #filePath)

// MARK: - Models

struct Config {
  var base = "origin/main"
  var dropPatterns = ["github-actions[bot]", "GitHub Actions"]
  var dryRun = false
  var verbose = false
}

struct Commit {
  let sha: String
  let authorName: String
  let authorEmail: String
  let parents: [String]
  let subject: String

  var shortSha: String { String(sha.prefix(8)) }
}

// MARK: - CLI

enum Option: String, CaseIterable {
  case base = "--base"
  case baseShort = "-b"
  case dryRun = "--dry-run"
  case dryRunShort = "-d"
  case verbose = "--verbose"
  case verboseShort = "-V"
  case help = "--help"
  case helpShort = "-h"

  static var completions: [String] { allCases.map(\.rawValue) }
}

func usage() -> String {
  """
  \(description)

  Usage:
    run drop-bot-commits [--base|-b <branch>] [--dry-run|-d] [--verbose|-V]

  Options:
    --base, -b       Base branch (default: origin/main)
    --dry-run, -d    Preview without making changes
    --verbose, -V    Show detailed output

  Notes:
    - Requires a clean working tree
    - Merge commits are blocked (flatten first)
  """
}

func parseArguments(_ args: [String]) throws -> Config {
  var config = Config()
  var index = 0
  while index < args.count {
    let arg = args[index]
    if arg == "--completions" {
      print(Option.completions.joined(separator: "\n"))
      exit(0)
    }
    guard let option = Option(rawValue: arg) else {
      throw ScriptError("Unknown argument: \(arg)")
    }
    switch option {
    case .base, .baseShort:
      guard index + 1 < args.count else { throw ScriptError("Missing value for --base") }
      config.base = args[index + 1]
      index += 2
    case .dryRun, .dryRunShort:
      config.dryRun = true
      index += 1
    case .verbose, .verboseShort:
      config.verbose = true
      index += 1
    case .help, .helpShort:
      print(usage())
      exit(0)
    }
  }
  return config
}

// MARK: - Git helpers

@discardableResult
func runGit(_ args: [String], config: Config, mutating: Bool = false) throws -> String {
  if config.dryRun && mutating {
    print("DRY RUN: git \(args.joined(separator: " "))")
    return ""
  }
  if config.verbose || (config.dryRun && mutating) {
    print("git \(args.joined(separator: " "))")
  }
  return try runCommand("git", args, emitOutput: false)
}

func gitDirURL(from repoRoot: String, gitDir: String) -> URL {
  gitDir.hasPrefix("/")
    ? URL(fileURLWithPath: gitDir)
    : URL(fileURLWithPath: repoRoot).appendingPathComponent(gitDir)
}

func ensureCleanWorkingTree(config: Config) throws {
  let status = try runGit(["status", "--porcelain"], config: config)
  guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw ScriptError("Working tree is not clean. Commit or stash changes first.")
  }
}

func ensureNoInProgressOperations(gitDir: URL) throws {
  let fm = FileManager.default
  if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path)
    || fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path)
  {
    throw ScriptError("Rebase is in progress. Finish or abort it first.")
  }
  if fm.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) {
    throw ScriptError("Cherry-pick is in progress. Finish or abort it first.")
  }
}

func parseRemoteAndBranch(from base: String) -> (remote: String, branch: String) {
  if let idx = base.firstIndex(of: "/") {
    return (String(base[..<idx]), String(base[base.index(after: idx)...]))
  }
  return ("origin", base)
}

func parseCommits(from logOutput: String) -> [Commit] {
  logOutput.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
    let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
    guard fields.count >= 5 else { return nil }
    return Commit(
      sha: String(fields[0]),
      authorName: String(fields[1]),
      authorEmail: String(fields[2]),
      parents: fields[3].split(separator: " ").map { String($0) },
      subject: String(fields[4])
    )
  }
}

func shouldDrop(_ commit: Commit, patterns: [String]) -> Bool {
  let name = commit.authorName.lowercased()
  let email = commit.authorEmail.lowercased()
  return patterns.contains { pattern in
    let target = pattern.lowercased()
    return name.contains(target) || email.contains(target)
  }
}

// MARK: - Entry point

@main
struct DropBotCommitsCommand {
  static func main() {
    runMain {
      let args = normalizeScriptArgs(
        Array(CommandLine.arguments.dropFirst()),
        scriptName: "drop-bot-commits"
      )
      let config = try parseArguments(args)

      let repoRoot = try runGit(["rev-parse", "--show-toplevel"], config: config)
      _ = FileManager.default.changeCurrentDirectoryPath(repoRoot)

      let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], config: config)
      guard branch != "HEAD" else {
        throw ScriptError("Detached HEAD. Check out a branch before running.")
      }

      let gitDir = gitDirURL(
        from: repoRoot,
        gitDir: try runGit(["rev-parse", "--git-dir"], config: config)
      )
      try ensureNoInProgressOperations(gitDir: gitDir)
      try ensureCleanWorkingTree(config: config)

      // Ensure base ref exists
      let baseRef = config.base
      do {
        _ = try runGit(["rev-parse", "--verify", baseRef], config: config)
      } catch {
        guard !config.dryRun else {
          throw ScriptError("Base ref \(baseRef) not found. Fetch it or run without --dry-run.")
        }
        let (remote, branch) = parseRemoteAndBranch(from: baseRef)
        _ = try runGit(["fetch", remote, branch], config: config, mutating: true)
        _ = try runGit(["rev-parse", "--verify", baseRef], config: config)
      }

      // Identify commits to process
      let mergeBase = try runGit(["merge-base", baseRef, "HEAD"], config: config)
      let logOutput = try runGit(
        ["log", "--reverse", "--format=%H%x1f%an%x1f%ae%x1f%P%x1f%s", "\(mergeBase)..HEAD"],
        config: config
      )
      let commits = parseCommits(from: logOutput)

      if commits.isEmpty {
        print("No commits found between \(mergeBase) and HEAD.")
      }

      // Block merge commits
      let mergeCommits = commits.filter { $0.parents.count > 1 }
      if !mergeCommits.isEmpty {
        let list = mergeCommits.map { "- \($0.shortSha) \($0.subject)" }.joined(separator: "\n")
        throw ScriptError("Merge commits detected. Flatten or remove them first.\n\(list)")
      }

      // Partition and process
      let dropCommits = commits.filter { shouldDrop($0, patterns: config.dropPatterns) }
      let keepCommits = commits.filter { !shouldDrop($0, patterns: config.dropPatterns) }

      if dropCommits.isEmpty {
        print("No GitHub Actions-authored commits to drop.")
      } else {
        print("Dropping \(dropCommits.count) GitHub Actions-authored commit(s):")
        for commit in dropCommits { print("- \(commit.shortSha) \(commit.subject)") }

        if config.dryRun {
          print(
            "DRY RUN: would reset to \(mergeBase) and cherry-pick \(keepCommits.count) commit(s).")
        } else {
          _ = try runGit(["reset", "--hard", mergeBase], config: config, mutating: true)
          if keepCommits.isEmpty {
            print("No commits left after dropping. Branch reset to \(mergeBase).")
          } else {
            print("Cherry-picking \(keepCommits.count) commit(s)...")
            for commit in keepCommits {
              _ = try runGit(["cherry-pick", commit.sha], config: config, mutating: true)
            }
          }
        }
      }

      // Fetch and rebase
      let (remote, branchName) = parseRemoteAndBranch(from: baseRef)
      if config.dryRun {
        print("DRY RUN: would fetch \(remote) \(branchName) and rebase onto \(baseRef).")
        return
      }
      _ = try runGit(["fetch", remote, branchName], config: config, mutating: true)
      _ = try runGit(["rebase", baseRef], config: config, mutating: true)
      print("Rebase complete.")
    }
  }
}
