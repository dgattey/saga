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

/// Builds the iOS Simulator app and screenshots its main screens without launching on this Mac.
func runUITests(repoRoot: String) throws {
  print("Capturing Saga screenshots in headless iOS Simulators...")
  try runCommand(
    "\(repoRoot)/scripts/ui-screenshots.sh", [], cwd: URL(fileURLWithPath: repoRoot))
}
