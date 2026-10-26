// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .executable(name: "Saga", targets: ["Saga"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/dgattey/dyl-kit",
      revision: "f0c1e619ed78c7a0aec245e9b94450fb5584dc2c"
    ),
    .package(url: "https://github.com/contentful/contentful.swift", from: "5.5.15"),
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
        .product(name: "Contentful", package: "contentful.swift"),
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
