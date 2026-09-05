#!/bin/bash
# Exercise SwiftPM's generated Bundle.module accessors in a relocated .app.
# The fixture has no external dependencies and never opens a UI.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/selectionbar-resources.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
fixture_dir="$test_dir/Fixture"
app_dir="$test_dir/Packaged App.app"

mkdir -p "$fixture_dir/Sources/ResourceProbe/Resources"
mkdir -p "$fixture_dir/Sources/ResourceDependency/Resources"
cat > "$fixture_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ResourceFixture",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "ResourceProbe", targets: ["ResourceProbe"])],
  targets: [
    .executableTarget(
      name: "ResourceProbe",
      dependencies: ["ResourceDependency"],
      resources: [.process("Resources")]
    ),
    .target(name: "ResourceDependency", resources: [.process("Resources")]),
  ]
)
SWIFT

cat > "$fixture_dir/Sources/ResourceDependency/ResourceDependency.swift" <<'SWIFT'
import Foundation

public func dependencyResource() throws -> (URL, String) {
  let url = Bundle.module.url(forResource: "dependency", withExtension: "txt")!
  return (url, try String(contentsOf: url, encoding: .utf8))
}
SWIFT

cat > "$fixture_dir/Sources/ResourceProbe/main.swift" <<'SWIFT'
import Foundation
import ResourceDependency

let appResource = Bundle.module.url(forResource: "icon", withExtension: "txt")!
let (dependencyURL, dependencyText) = try dependencyResource()
let appText = try String(contentsOf: appResource, encoding: .utf8)
precondition(appText == "app resource\n")
precondition(dependencyText == "dependency resource\n")
let packagedResources = Bundle.main.bundleURL
  .appendingPathComponent("Contents/Resources").resolvingSymlinksInPath().path + "/"
for url in [appResource, dependencyURL] {
  precondition(url.resolvingSymlinksInPath().path.hasPrefix(packagedResources))
}
print("PASS: executable and dependency resources loaded from the packaged app")
SWIFT

echo "app resource" > "$fixture_dir/Sources/ResourceProbe/Resources/icon.txt"
echo "dependency resource" > "$fixture_dir/Sources/ResourceDependency/Resources/dependency.txt"
bash "$script_dir/swift-build-app.sh" --package-path "$fixture_dir" --configuration release --product ResourceProbe --arch "$(uname -m)"
bin_dir="$(bash "$script_dir/swift-build-app.sh" --package-path "$fixture_dir" --configuration release --show-bin-path --arch "$(uname -m)")"

mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/ResourceProbe" "$app_dir/Contents/MacOS/ResourceProbe"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ResourceProbe</string>
  <key>CFBundleIdentifier</key><string>com.selectionbar.resource-packaging-test</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

bash "$script_dir/embed-resource-bundles.sh" "$bin_dir" "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
# Remove the absolute build-time fallback used by SwiftPM's generated accessor.
mv "$fixture_dir/.build" "$fixture_dir/build-unavailable"

# Match the release script's copy into the DMG staging directory.
mkdir "$test_dir/Installed"
cp -R "$app_dir" "$test_dir/Installed/"
app_dir="$test_dir/Installed/Packaged App.app"
codesign --verify --deep --strict "$app_dir"

"$app_dir/Contents/MacOS/ResourceProbe" -AppleLanguages '(en)'
"$app_dir/Contents/MacOS/ResourceProbe" -AppleLanguages '(zh-Hant-HK)' -AppleLocale zh_HK
