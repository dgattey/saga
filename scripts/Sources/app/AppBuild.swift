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

private struct ResolvedPackagesFile: Decodable {
  struct Pin: Decodable {
    struct State: Decodable {
      let revision: String
    }
    let identity: String
    let state: State
  }
  let pins: [Pin]
}

private struct WorkspaceStateFile: Decodable {
  struct ObjectPayload: Decodable {
    struct Dependency: Decodable {
      struct PackageRef: Decodable {
        let identity: String
      }
      struct State: Decodable {
        struct CheckoutState: Decodable {
          let revision: String
        }
        let checkoutState: CheckoutState?
      }
      let packageRef: PackageRef
      let state: State
      let subpath: String
    }
    let dependencies: [Dependency]
  }
  let object: ObjectPayload
}

func hasUpToDateResolvedPackages(projectPath: String, derivedDataPath: String) -> Bool {
  let fileManager = FileManager.default
  let resolvedURL = URL(fileURLWithPath: projectPath)
    .appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
  let sourcePackagesURL = URL(fileURLWithPath: derivedDataPath)
    .appendingPathComponent("SourcePackages")
  let workspaceStateURL = sourcePackagesURL.appendingPathComponent("workspace-state.json")
  let checkoutsURL = sourcePackagesURL.appendingPathComponent("checkouts")

  guard
    let resolvedData = try? Data(contentsOf: resolvedURL),
    let workspaceData = try? Data(contentsOf: workspaceStateURL),
    let resolved = try? JSONDecoder().decode(ResolvedPackagesFile.self, from: resolvedData),
    let workspace = try? JSONDecoder().decode(WorkspaceStateFile.self, from: workspaceData),
    !resolved.pins.isEmpty
  else {
    return false
  }

  var checkedOutRevisions: [String: (revision: String, subpath: String)] = [:]
  for dependency in workspace.object.dependencies {
    guard let revision = dependency.state.checkoutState?.revision else { continue }
    checkedOutRevisions[dependency.packageRef.identity.lowercased()] = (
      revision, dependency.subpath
    )
  }

  for pin in resolved.pins {
    guard let match = checkedOutRevisions[pin.identity.lowercased()],
      match.revision == pin.state.revision
    else {
      return false
    }
    let checkoutPath = checkoutsURL.appendingPathComponent(match.subpath).path
    if !fileManager.fileExists(atPath: checkoutPath) {
      return false
    }
  }

  return true
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

func runUnitTests(
  projectPath: String,
  derivedDataPath: String,
  arch: String,
  verbose: Bool,
  skipSigning: Bool
) throws {
  print("Running Saga unit tests (SagaTests)...")
  var args = [
    "-project", projectPath,
    "-scheme", "Saga",
    "-configuration", "Debug",
    "-destination", "platform=macOS,arch=\(arch)",
    "-only-testing:SagaTests",
  ]
  if hasUpToDateResolvedPackages(projectPath: projectPath, derivedDataPath: derivedDataPath) {
    args.append("-disableAutomaticPackageResolution")
  }
  args.append("test")
  if !verbose {
    args.insert("-quiet", at: 0)
  }
  if skipSigning {
    args.append(contentsOf: [
      "CODE_SIGN_IDENTITY=-",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO",
    ])
  }

  try runCommand("xcodebuild", args)
}
