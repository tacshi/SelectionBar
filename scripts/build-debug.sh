#!/bin/bash
# Build SelectionBar and package it as a local debug .app bundle.
#
# Usage:
#   ./scripts/build-debug.sh
#   ./scripts/build-debug.sh --arch x86_64
#   ./scripts/build-debug.sh --no-format
#   ./scripts/build-debug.sh --no-sign
#   ./scripts/build-debug.sh --clean
#
# Signing:
#   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
#   If DEVELOPER_ID_APPLICATION is unset, the script falls back to ad-hoc signing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SelectionBar"
JS_HELPER_NAME="selectionbar-js-helper"
EXECUTABLE_NAME="SelectionBarApp"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
ICON_ICNS_SOURCE="$SCRIPT_DIR/Assets/AppIcon.icns"
ICONSET_SOURCE="$SCRIPT_DIR/Assets/AppIcon.iconset"
CONFIGURATION="debug"
ARCH=""
DO_FORMAT=true
DO_SIGN=true
DO_CLEAN=false

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --debug         Build debug configuration (default)
  --arch ARCH     Build for architecture (arm64 or x86_64)
  --no-format     Skip swift-format step
  --no-sign       Skip code signing
  --clean         Remove .build and app bundle before building
  -h, --help      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --no-format)
      DO_FORMAT=false
      shift
      ;;
    --no-sign)
      DO_SIGN=false
      shift
      ;;
    --clean)
      DO_CLEAN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [ "$DO_CLEAN" = true ]; then
  echo "🧹 Cleaning previous artifacts..."
  rm -rf "$SCRIPT_DIR/.build" "$APP_DIR"
fi

if [ "$DO_FORMAT" = true ]; then
  # Prefer the toolchain formatter, which is what CI runs. A Homebrew
  # swift-format on PATH can be a different version and format differently,
  # so it is only the fallback.
  SWIFT_FORMAT=""
  if xcrun --find swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="$(xcrun --find swift-format)"
  elif command -v swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="$(command -v swift-format)"
  fi

  if [ -n "$SWIFT_FORMAT" ]; then
    echo "🎨 Formatting Swift code..."
    "$SWIFT_FORMAT" --recursive --in-place "$SCRIPT_DIR/Sources" "$SCRIPT_DIR/Tests" "$SCRIPT_DIR/Package.swift"
  else
    echo "⚠️  swift-format not found; skipping formatting"
  fi
fi

echo "🔨 Building $EXECUTABLE_NAME ($CONFIGURATION)..."
BUILD_ARGS=("-c" "$CONFIGURATION" "--product" "$EXECUTABLE_NAME")
if [ -n "$ARCH" ]; then
  BUILD_ARGS+=("--arch" "$ARCH")
fi

cd "$SCRIPT_DIR"
swift build "${BUILD_ARGS[@]}"

# The JavaScript helper is a separate product; without building it explicitly
# the bundle would ship without it and silently fall back to uninterruptible
# in-process script execution.
JS_HELPER_ARGS=("-c" "$CONFIGURATION" "--product" "$JS_HELPER_NAME")
if [ -n "$ARCH" ]; then
  JS_HELPER_ARGS+=("--arch" "$ARCH")
fi
swift build "${JS_HELPER_ARGS[@]}"

BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [ ! -f "$BINARY_PATH" ]; then
  echo "❌ Build succeeded but binary not found at: $BINARY_PATH"
  exit 1
fi

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

# Copy and rename executable
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Fix rpaths for framework loading
install_name_tool -delete_rpath "/usr/lib/swift" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
install_name_tool -delete_rpath "@loader_path" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
for rpath in $(otool -l "$APP_DIR/Contents/MacOS/$APP_NAME" | grep -A2 LC_RPATH | grep "path /Applications/Xcode" | awk '{print $2}'); do
  install_name_tool -delete_rpath "$rpath" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Copy Sparkle framework
SPARKLE_COPIED=false
for sparkle_path in \
    "$BIN_DIR/Sparkle.framework" \
    "$BIN_DIR/Sparkle_Sparkle.framework" \
    "$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.framework"; do
  if [ -d "$sparkle_path" ]; then
    echo "   Copying Sparkle framework from: $sparkle_path"
    cp -R "$sparkle_path" "$APP_DIR/Contents/Frameworks/"
    SPARKLE_COPIED=true
    break
  fi
done
if [ "$SPARKLE_COPIED" = false ]; then
  echo "⚠️  Sparkle.framework not found in build output"
fi

# Embed the JavaScript helper. Scripts run in this child process so a runaway
# script can be killed outright instead of pinning a core inside SelectionBar.
JS_HELPER_SRC="$BIN_DIR/$JS_HELPER_NAME"
if [ ! -f "$JS_HELPER_SRC" ]; then
  echo "❌ $JS_HELPER_NAME not found at: $JS_HELPER_SRC"
  exit 1
fi
echo "   Embedding JavaScript helper"
mkdir -p "$APP_DIR/Contents/Helpers"
cp "$JS_HELPER_SRC" "$APP_DIR/Contents/Helpers/$JS_HELPER_NAME"
chmod +x "$APP_DIR/Contents/Helpers/$JS_HELPER_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP_DIR/Contents/Helpers/$JS_HELPER_NAME" 2>/dev/null || true

# Copy static Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/"

# Copy resource bundles
for bundle in "$BIN_DIR"/*.bundle; do
  if [ -d "$bundle" ]; then
    bundle_name="$(basename "$bundle")"
    echo "   Copying bundle: $bundle_name"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    chmod -R u+w "$APP_DIR/Contents/Resources/$bundle_name"
  fi
done

# Compile .xcstrings -> .lproj for localization support.
# We compile both:
# 1) copied app bundles in Contents/Resources
# 2) original SwiftPM .build bundles (Bundle.module fallback path)
for base_dir in "$APP_DIR/Contents/Resources" "$BIN_DIR"; do
  for app_bundle in "$base_dir"/SelectionBar_*.bundle; do
    if [ -f "$app_bundle/Localizable.xcstrings" ]; then
      # Derive source path: SelectionBar_SelectionBarApp.bundle -> Sources/SelectionBarApp/Resources/Localizable.xcstrings
      target_name=$(basename "$app_bundle" | sed 's/SelectionBar_//' | sed 's/\.bundle//')
      xcstrings_source="$SCRIPT_DIR/Sources/$target_name/Resources/Localizable.xcstrings"
      if [ -f "$xcstrings_source" ]; then
        echo "   Compiling localization: $(basename "$app_bundle") ($(basename "$base_dir"))"
        xcrun xcstringstool compile "$xcstrings_source" \
          --output-directory "$app_bundle" \
          --language en --language ja --language zh-Hans
      fi
    fi
  done
done

# Also compile App target strings into the main Resources for SwiftUI auto-localization
if [ -f "$SCRIPT_DIR/Sources/SelectionBarApp/Resources/Localizable.xcstrings" ]; then
  echo "   Compiling main bundle localization..."
  xcrun xcstringstool compile "$SCRIPT_DIR/Sources/SelectionBarApp/Resources/Localizable.xcstrings" \
    --output-directory "$APP_DIR/Contents/Resources" \
    --language en --language ja --language zh-Hans
fi

# App icon must come from pre-generated assets.
if [ -f "$ICON_ICNS_SOURCE" ]; then
  echo "🎨 Copying app icon from assets..."
  cp "$ICON_ICNS_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -d "$ICONSET_SOURCE" ]; then
  if command -v iconutil >/dev/null 2>&1; then
    echo "🎨 Building app icon from assets iconset..."
    iconutil -c icns "$ICONSET_SOURCE" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  else
    echo "⚠️  iconutil not found; skipping app icon generation"
  fi
else
  echo "⚠️  Icon assets not found. Expected one of:"
  echo "   - $ICON_ICNS_SOURCE"
  echo "   - $ICONSET_SOURCE"
fi

echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

if [ "$DO_SIGN" = true ]; then
  if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
    if [ -n "$SIGN_IDENTITY" ]; then
      echo "🔑 Signing app bundle with DEVELOPER_ID_APPLICATION: $SIGN_IDENTITY"
    else
      SIGN_IDENTITY="-"
      echo "🔑 DEVELOPER_ID_APPLICATION not set; signing app bundle ad-hoc"
    fi

    # Sign Sparkle framework components
    SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FRAMEWORK" ]; then
      for xpc in "$SPARKLE_FRAMEWORK/Versions/B/XPCServices"/*.xpc; do
        [ -d "$xpc" ] && codesign --force --sign "$SIGN_IDENTITY" --options runtime "$xpc"
      done
      for app in "$SPARKLE_FRAMEWORK/Versions/B"/*.app; do
        [ -d "$app" ] && codesign --force --sign "$SIGN_IDENTITY" --options runtime "$app"
      done
      for exe in "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"; do
        [ -f "$exe" ] && codesign --force --sign "$SIGN_IDENTITY" --options runtime "$exe"
      done
      codesign --force --sign "$SIGN_IDENTITY" --options runtime "$SPARKLE_FRAMEWORK"
    fi

    # Sign the embedded JavaScript helper before the outer bundle
    JS_HELPER="$APP_DIR/Contents/Helpers/$JS_HELPER_NAME"
    if [ -f "$JS_HELPER" ]; then
      codesign --force --sign "$SIGN_IDENTITY" --options runtime "$JS_HELPER"
    fi

    # Sign main app with entitlements
    codesign --force --sign "$SIGN_IDENTITY" \
      --entitlements "$SCRIPT_DIR/SelectionBar.entitlements" \
      --options runtime \
      "$APP_DIR"
  else
    echo "⚠️  codesign not found; skipping signing"
  fi
fi

echo "✅ App bundle created: $APP_DIR"
echo "   Open with: open \"$APP_DIR\""
