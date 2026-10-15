import Common
import CryptoKit
import Foundation

func currentBranchName(repoRoot: String) -> String? {
  let output =
    (try? runCommand(
      "git", ["rev-parse", "--abbrev-ref", "HEAD"],
      cwd: URL(fileURLWithPath: repoRoot),
      allowFailure: true,
      emitOutput: false
    )) ?? ""
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty, trimmed != "HEAD" else { return nil }
  return trimmed
}

func currentShortCommit(repoRoot: String) -> String? {
  let output =
    (try? runCommand(
      "git", ["rev-parse", "--short", "HEAD"],
      cwd: URL(fileURLWithPath: repoRoot),
      allowFailure: true,
      emitOutput: false
    )) ?? ""
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

func sha256Hex(_ value: String) -> String {
  let digest = SHA256.hash(data: Data(value.utf8))
  return digest.map { String(format: "%02x", $0) }.joined()
}

func buildCacheKey(repoRoot: String) -> String {
  if let branch = currentBranchName(repoRoot: repoRoot) {
    return sha256Hex(branch)
  }
  if let shortCommit = currentShortCommit(repoRoot: repoRoot) {
    return shortCommit
  }
  return "unknown"
}

func hasUpToDateResolvedPackages(projectPath: String, derivedDataPath: String) -> Bool {
  let fileManager = FileManager.default
  let checkoutsPath = URL(fileURLWithPath: derivedDataPath)
    .appendingPathComponent("SourcePackages/checkouts")
    .path
  guard
    let checkoutEntries = try? fileManager.contentsOfDirectory(atPath: checkoutsPath),
    !checkoutEntries.isEmpty
  else {
    return false
  }

  let resolvedPath = URL(fileURLWithPath: projectPath)
    .appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    .path
  guard
    let resolvedAttrs = try? fileManager.attributesOfItem(atPath: resolvedPath),
    let checkoutsAttrs = try? fileManager.attributesOfItem(atPath: checkoutsPath),
    let resolvedDate = resolvedAttrs[.modificationDate] as? Date,
    let checkoutsDate = checkoutsAttrs[.modificationDate] as? Date
  else {
    return true
  }

  return checkoutsDate >= resolvedDate
}

func buildApp(
  projectPath: String,
  derivedDataPath: String,
  arch: String,
  configuration: String = "Debug",
  verbose: Bool,
  skipSigning: Bool
) throws {
  print("Building Saga (\(configuration))...")
  // Uses standard DerivedData location for hot reload compatibility
  var args = [
    "-project", projectPath,
    "-scheme", "Saga",
    "-configuration", configuration,
    "-destination", "platform=macOS,arch=\(arch)",
  ]
  if hasUpToDateResolvedPackages(projectPath: projectPath, derivedDataPath: derivedDataPath) {
    args.append("-disableAutomaticPackageResolution")
  }
  args.append("build")
  if !verbose {
    args.insert("-quiet", at: 0)
  }
  // Skip code signing for CI environments without certificates
  if skipSigning {
    args.append(contentsOf: [
      "CODE_SIGN_IDENTITY=-",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO",
    ])
  }

  try runCommand("xcodebuild", args)
}
