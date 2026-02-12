// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SelectionBar",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "SelectionBarApp", targets: ["SelectionBarApp"]),
    .library(name: "SelectionBarCore", targets: ["SelectionBarCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.1")
  ],
  targets: [
    .executableTarget(
      name: "SelectionBarApp",
      dependencies: ["SelectionBarCore", "Sparkle"],
      path: "Sources/SelectionBarApp",
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "SelectionBarCore",
      path: "Sources/SelectionBarCore",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "SelectionBarCoreTests",
      dependencies: ["SelectionBarCore"],
      path: "Tests/SelectionBarCoreTests"
    ),
    .testTarget(
      name: "SelectionBarAppTests",
      dependencies: ["SelectionBarApp", "SelectionBarCore"],
      path: "Tests/SelectionBarAppTests"
    ),
  ]
)
