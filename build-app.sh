#!/bin/bash
# Build SelectionBar and package it as a local .app bundle.
#
# Usage:
#   ./build-app.sh
#   ./build-app.sh --debug
#   ./build-app.sh --arch x86_64
#   ./build-app.sh --no-format
#   ./build-app.sh --no-sign
#   ./build-app.sh --clean

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SelectionBar"
EXECUTABLE_NAME="SelectionBarApp"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
ICON_ICNS_SOURCE="$SCRIPT_DIR/Assets/AppIcon.icns"
ICONSET_SOURCE="$SCRIPT_DIR/Assets/AppIcon.iconset"
CONFIGURATION="release"
ARCH=""
DO_FORMAT=true
DO_SIGN=true
DO_CLEAN=false

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --debug         Build debug configuration (default: release)
  --arch ARCH     Build for architecture (arm64 or x86_64)
  --no-format     Skip swift-format step
  --no-sign       Skip ad-hoc code signing
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
  if command -v swift-format >/dev/null 2>&1; then
    echo "🎨 Formatting Swift code..."
    swift-format --recursive --in-place "$SCRIPT_DIR/Sources" "$SCRIPT_DIR/Tests" "$SCRIPT_DIR/Package.swift"
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

# Copy static Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/"

# Copy resource bundles
for bundle in "$BIN_DIR"/*.bundle; do
  if [ -d "$bundle" ]; then
    echo "   Copying bundle: $(basename "$bundle")"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    chmod -R u+w "$APP_DIR/Contents/Resources/$(basename "$bundle")"
  fi
done

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
    echo "🔑 Signing app bundle..."

    # Sign Sparkle framework components
    SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FRAMEWORK" ]; then
      for xpc in "$SPARKLE_FRAMEWORK/Versions/B/XPCServices"/*.xpc; do
        [ -d "$xpc" ] && codesign --force --sign "-" --options runtime "$xpc"
      done
      for app in "$SPARKLE_FRAMEWORK/Versions/B"/*.app; do
        [ -d "$app" ] && codesign --force --sign "-" --options runtime "$app"
      done
      for exe in "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"; do
        [ -f "$exe" ] && codesign --force --sign "-" --options runtime "$exe"
      done
      codesign --force --sign "-" --options runtime "$SPARKLE_FRAMEWORK"
    fi

    # Sign main app with entitlements
    codesign --force --sign "-" \
      --entitlements "$SCRIPT_DIR/SelectionBar.entitlements" \
      --options runtime \
      "$APP_DIR"
  else
    echo "⚠️  codesign not found; skipping signing"
  fi
fi

echo "✅ App bundle created: $APP_DIR"
echo "   Open with: open \"$APP_DIR\""
