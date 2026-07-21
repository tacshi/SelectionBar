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
    // Bundled into the app at Contents/Helpers so JavaScript actions run in a
    // process that can be killed outright when a script will not stop.
    .executable(name: "selectionbar-js-helper", targets: ["SelectionBarJSHelper"]),
    .library(name: "SelectionBarCore", targets: ["SelectionBarCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", from: "2.3.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.1"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
  ],
  targets: [
    .executableTarget(
      name: "SelectionBarApp",
      dependencies: [
        "SelectionBarCore",
        "Sparkle",
        .product(name: "PermissionFlow", package: "PermissionFlow"),
        .product(name: "PermissionFlowInputMonitoringStatus", package: "PermissionFlow"),
      ],
      path: "Sources/SelectionBarApp",
      resources: [
        .process("Resources")
      ]
    ),
    // The JavaScriptCore engine, shared by the in-process fallback in
    // SelectionBarCore and by the out-of-process helper.
    .target(
      name: "SelectionBarJavaScriptEngine",
      path: "Sources/SelectionBarJavaScriptEngine"
    ),
    .executableTarget(
      name: "SelectionBarJSHelper",
      dependencies: ["SelectionBarJavaScriptEngine"],
      path: "Sources/SelectionBarJSHelper"
    ),
    .target(
      name: "SelectionBarCore",
      dependencies: [
        "SelectionBarJavaScriptEngine",
        .product(name: "PermissionFlow", package: "PermissionFlow"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
      ],
      path: "Sources/SelectionBarCore",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "SelectionBarCoreTests",
      dependencies: ["SelectionBarCore", "SelectionBarJavaScriptEngine"],
      path: "Tests/SelectionBarCoreTests"
    ),
    .testTarget(
      name: "SelectionBarAppTests",
      dependencies: ["SelectionBarApp", "SelectionBarCore"],
      path: "Tests/SelectionBarAppTests",
      linkerSettings: [
        // The xctest bundle sits at Products/Debug/SelectionBarAppTests.xctest/
        // Contents/MacOS/, but Sparkle.framework is built into Products/Debug.
        // Without this rpath entry the bundle cannot be dlopen'd and `swift
        // test` fails before running a single test.
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])
      ]
    ),
  ]
)
