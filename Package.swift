// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .executable(name: "Saga", targets: ["Saga"])
  ],
  dependencies: [
    .package(url: "https://github.com/dgattey/dyl-kit", from: "0.4.0"),
    .package(url: "https://github.com/contentful/contentful-persistence.swift", from: "0.18.2"),
    .package(url: "https://github.com/ukushu/Ifrit", from: "4.0.0"),
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.5"),
  ],
  targets: [
    .executableTarget(
      name: "Saga",
      dependencies: [
        .product(name: "DylCore", package: "dyl-kit"),
        .product(name: "DylUI", package: "dyl-kit"),
        .product(name: "DylUpdates", package: "dyl-kit"),
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
        .product(name: "DylUI", package: "dyl-kit"),
        .product(name: "ViewInspector", package: "ViewInspector"),
      ]
    ),
  ]
)
