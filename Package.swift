// swift-tools-version: 6.2
import PackageDescription

// DylKit lives in scone-os until github.com/dgattey/dyl-kit exists. `./run` clones it into .dylkit;
// DYLKIT_PATH points at another checkout of its Packages/DylKit.
let dylKitPath = Context.environment["DYLKIT_PATH"] ?? ".dylkit/scone-os/Packages/DylKit"

let package = Package(
  name: "Saga",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .executable(name: "Saga", targets: ["Saga"])
  ],
  dependencies: [
    .package(path: dylKitPath),
    .package(url: "https://github.com/contentful/contentful-persistence.swift", from: "0.18.2"),
    .package(url: "https://github.com/ukushu/Ifrit", from: "4.0.0"),
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.5"),
  ],
  targets: [
    .executableTarget(
      name: "Saga",
      dependencies: [
        .product(name: "DylCore", package: "DylKit"),
        .product(name: "DylUI", package: "DylKit"),
        .product(name: "DylUpdates", package: "DylKit"),
        .product(name: "ContentfulPersistence", package: "contentful-persistence.swift"),
        .product(name: "IfritStatic", package: "Ifrit"),
      ],
      // Bundler compiles these into the app ([build] resources and icon in DylApp.toml).
      exclude: ["AppIcon.icon", "Assets.xcassets", "Saga.xcdatamodeld"]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: [
        "Saga",
        .product(name: "DylUI", package: "DylKit"),
        .product(name: "ViewInspector", package: "ViewInspector"),
      ]
    ),
  ]
)
