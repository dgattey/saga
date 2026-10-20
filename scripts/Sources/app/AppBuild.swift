import Common
import Foundation

/// Builds `build/Saga.app` with `scripts/build-macos.sh` and returns its path.
func buildApp(repoRoot: String, release: Bool) throws -> String {
  let configuration = release ? "release" : "debug"
  print("Building Saga (\(configuration))...")
  try runCommand(
    "\(repoRoot)/scripts/build-macos.sh",
    [configuration],
    cwd: URL(fileURLWithPath: repoRoot)
  )
  return "\(repoRoot)/build/Saga.app"
}

func runUnitTests(repoRoot: String) throws {
  print("Running Saga unit tests (SagaTests)...")
  try runCommand("swift", ["test"], cwd: URL(fileURLWithPath: repoRoot))
}
