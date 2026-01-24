#!/usr/bin/env swift

import Foundation

// Simple CLI that removes GitHub Actions-authored commits from the current branch
// and rebases onto a base branch (default: origin/main).

struct Config {
    var base = "origin/main"
    var dropPatterns = ["github-actions[bot]", "GitHub Actions"]
    var dryRun = false
    var verbose = false
}

// Minimal commit metadata for deciding what to drop and replay.
struct Commit {
    let sha: String
    let authorName: String
    let authorEmail: String
    let parents: [String]
    let subject: String

    var shortSha: String {
        String(sha.prefix(8))
    }
}

struct ScriptError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

func usage() -> String {
    """
    Drops GitHub Actions-authored commits on the current branch, then fetches and rebases onto the base branch.

    Usage:
      clean-actions-rebase.swift [--base origin/main] [--dry-run] [--verbose]
      clean-actions-rebase.swift [-b origin/main] [-d] [-V]

    Defaults:
      base: origin/main
      drop patterns: github-actions[bot], GitHub Actions

    Notes:
      - Requires a clean working tree.
      - Merge commits are blocked (flatten or remove them first).
    """
}

// Runs a command and returns stdout or throws with stderr.
@discardableResult
func runCommand(_ command: String, _ args: [String], allowFailure: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + args
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

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

    if process.terminationStatus != 0 {
        if allowFailure {
            return stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let combined = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ScriptError(message: "Command failed: \(command) \(args.joined(separator: " "))\n\(combined)")
    }

    return stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Wrapper for git invocations with dry-run and verbose output.
@discardableResult
func runGit(_ args: [String], config: Config, mutating: Bool = false) throws -> String {
    if config.dryRun && mutating {
        print("DRY RUN: git \(args.joined(separator: " "))")
        return ""
    }
    if config.verbose || (config.dryRun && mutating) {
        print("git \(args.joined(separator: " "))")
    }
    return try runCommand("git", args)
}

// Parses CLI arguments into a config object.
func parseArguments() throws -> Config {
    var config = Config()

    let args = Array(CommandLine.arguments.dropFirst())

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--base", "-b":
            guard index + 1 < args.count else {
                throw ScriptError(message: "Missing value for --base")
            }
            config.base = args[index + 1]
            index += 2
        case "--dry-run", "-d":
            config.dryRun = true
            index += 1
        case "--verbose", "-V":
            config.verbose = true
            index += 1
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw ScriptError(message: "Unknown argument: \(arg)")
        }
    }

    return config
}

// Resolves .git paths for both normal and worktree setups.
func gitDirURL(from repoRoot: String, gitDir: String) -> URL {
    if gitDir.hasPrefix("/") {
        return URL(fileURLWithPath: gitDir)
    }
    return URL(fileURLWithPath: repoRoot).appendingPathComponent(gitDir)
}

// Ensures we won't clobber local changes.
func ensureCleanWorkingTree(config: Config) throws {
    let status = try runGit(["status", "--porcelain"], config: config)
    if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw ScriptError(message: "Working tree is not clean. Commit or stash changes first.")
    }
}

// Avoids interfering with other git operations.
func ensureNoInProgressOperations(gitDir: URL) throws {
    let fm = FileManager.default
    let rebaseApply = gitDir.appendingPathComponent("rebase-apply").path
    let rebaseMerge = gitDir.appendingPathComponent("rebase-merge").path
    let cherryPickHead = gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path

    if fm.fileExists(atPath: rebaseApply) || fm.fileExists(atPath: rebaseMerge) {
        throw ScriptError(message: "Rebase is in progress. Finish or abort it first.")
    }
    if fm.fileExists(atPath: cherryPickHead) {
        throw ScriptError(message: "Cherry-pick is in progress. Finish or abort it first.")
    }
}

// Supports "origin/main" or "main" inputs.
func parseRemoteAndBranch(from base: String) -> (remote: String, branch: String) {
    if let slashIndex = base.firstIndex(of: "/") {
        let remote = String(base[..<slashIndex])
        let branch = String(base[base.index(after: slashIndex)...])
        return (remote, branch)
    }
    return ("origin", base)
}

// Parses git log output into typed commit data.
func parseCommits(from logOutput: String) -> [Commit] {
    let lines = logOutput.split(separator: "\n", omittingEmptySubsequences: true)
    return lines.compactMap { line in
        let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard fields.count >= 5 else { return nil }
        let sha = String(fields[0])
        let authorName = String(fields[1])
        let authorEmail = String(fields[2])
        let parents = fields[3].split(separator: " ").map { String($0) }
        let subject = String(fields[4])
        return Commit(sha: sha, authorName: authorName, authorEmail: authorEmail, parents: parents, subject: subject)
    }
}

// Checks author name/email against the drop patterns.
func shouldDrop(_ commit: Commit, patterns: [String]) -> Bool {
    let name = commit.authorName.lowercased()
    let email = commit.authorEmail.lowercased()
    return patterns.contains { pattern in
        let target = pattern.lowercased()
        return name.contains(target) || email.contains(target)
    }
}

func main() throws {
    let config = try parseArguments()

    // Anchor execution in the repo root.
    let repoRoot = try runGit(["rev-parse", "--show-toplevel"], config: config)
    _ = FileManager.default.changeCurrentDirectoryPath(repoRoot)

    // Require an actual branch.
    let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], config: config)
    if branch == "HEAD" {
        throw ScriptError(message: "Detached HEAD. Check out a branch before running.")
    }

    // Ensure no in-progress git operation and a clean working tree.
    let gitDirRaw = try runGit(["rev-parse", "--git-dir"], config: config)
    let gitDir = gitDirURL(from: repoRoot, gitDir: gitDirRaw)

    try ensureNoInProgressOperations(gitDir: gitDir)
    try ensureCleanWorkingTree(config: config)

    // Ensure the base ref exists locally (fetch if needed).
    let baseRef = config.base
    do {
        _ = try runGit(["rev-parse", "--verify", baseRef], config: config)
    } catch {
        if config.dryRun {
            throw ScriptError(message: "Base ref \(baseRef) not found. Fetch it or run without --dry-run.")
        }
        let (remote, branch) = parseRemoteAndBranch(from: baseRef)
        _ = try runGit(["fetch", remote, branch], config: config, mutating: true)
        _ = try runGit(["rev-parse", "--verify", baseRef], config: config)
    }

    // Identify the commits on this branch since it diverged from base.
    let mergeBase = try runGit(["merge-base", baseRef, "HEAD"], config: config)
    let logOutput = try runGit([
        "log",
        "--reverse",
        "--format=%H%x1f%an%x1f%ae%x1f%P%x1f%s",
        "\(mergeBase)..HEAD"
    ], config: config)

    let commits = parseCommits(from: logOutput)
    if commits.isEmpty {
        print("No commits found between \(mergeBase) and HEAD.")
    }

    // Merge commits can't be safely flattened without explicit intent.
    let mergeCommits = commits.filter { $0.parents.count > 1 }
    if !mergeCommits.isEmpty {
        let list = mergeCommits.map { "- \($0.shortSha) \($0.subject)" }.joined(separator: "\n")
        throw ScriptError(message: "Merge commits detected. Flatten or remove them first.\n\(list)")
    }

    // Partition commits into drop/keep buckets.
    let dropCommits = commits.filter { shouldDrop($0, patterns: config.dropPatterns) }
    let keepCommits = commits.filter { !shouldDrop($0, patterns: config.dropPatterns) }

    if dropCommits.isEmpty {
        print("No GitHub Actions-authored commits to drop.")
    } else {
        print("Dropping \(dropCommits.count) GitHub Actions-authored commit(s):")
        for commit in dropCommits {
            print("- \(commit.shortSha) \(commit.subject)")
        }

        if config.dryRun {
            print("DRY RUN: would reset to \(mergeBase) and cherry-pick \(keepCommits.count) commit(s).")
        } else {
            // Rebuild branch history without the dropped commits.
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

    // Fetch and rebase onto the base ref.
    let (remote, branchName) = parseRemoteAndBranch(from: baseRef)
    if config.dryRun {
        print("DRY RUN: would fetch \(remote) \(branchName) and rebase onto \(baseRef).")
        return
    }

    _ = try runGit(["fetch", remote, branchName], config: config, mutating: true)
    _ = try runGit(["rebase", baseRef], config: config, mutating: true)
    print("Rebase complete.")
}

do {
    try main()
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
