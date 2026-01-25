// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "SagaScripts",
  targets: [
    .target(name: "Common"),
    .executableTarget(name: "bootstrap", dependencies: ["Common"]),
    .executableTarget(name: "checks", dependencies: ["Common"]),
    .executableTarget(name: "drop-bot-commits", dependencies: ["Common"]),
    .executableTarget(name: "version-and-release", dependencies: ["Common"]),
    .executableTarget(name: "app", dependencies: ["Common"]),
  ]
)
