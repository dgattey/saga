// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SagaScripts",
  platforms: [
    .macOS(.v15)
  ],
  targets: [
    .target(name: "Common"),
    .executableTarget(name: "bootstrap", dependencies: ["Common"]),
    .executableTarget(name: "checks", dependencies: ["Common"]),
    .executableTarget(name: "config", dependencies: ["Common"]),
    .executableTarget(name: "drop-bot-commits", dependencies: ["Common"]),
    .executableTarget(name: "version-and-release", dependencies: ["Common"]),
    .executableTarget(name: "app", dependencies: ["Common"]),
    .executableTarget(name: "clean", dependencies: ["Common"]),
  ]
)
