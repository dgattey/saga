// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .executable(name: "Saga", targets: ["Saga"])
  ],
  dependencies: [
    .package(url: "https://github.com/contentful/contentful-persistence.swift", from: "0.18.2"),
    .package(url: "https://github.com/ukushu/Ifrit", from: "4.0.0"),
    // macOS auto-update (canonical for non-App-Store apps). Linked only into the macOS app.
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.5"),
  ],
  targets: [
    .executableTarget(
      name: "Saga",
      dependencies: [
        .product(name: "ContentfulPersistence", package: "contentful-persistence.swift"),
        .product(name: "IfritStatic", package: "Ifrit"),
        .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
      ],
      path: "Saga/Saga",
      // scripts/build-macos.sh and scripts/build-ios-sim.sh compile these into the app bundle.
      exclude: ["AppIcon.icon", "Assets.xcassets", "Saga.xcdatamodeld"],
      linkerSettings: [
        // build-macos.sh embeds Sparkle.framework under Contents/Frameworks.
        .unsafeFlags(
          ["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"],
          .when(platforms: [.macOS])
        )
      ]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: [
        "Saga",
        .product(name: "ViewInspector", package: "ViewInspector"),
      ],
      path: "Saga/SagaTests"
    ),
  ],
  swiftLanguageModes: [.v5]
)
