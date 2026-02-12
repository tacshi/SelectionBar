#!/bin/bash
# Automated release script for SelectionBar
# Usage: ./release.sh VERSION [OPTIONS]
#
# Examples:
#   ./release.sh 0.1.2              # Full release (all architectures + GitHub)
#   ./release.sh 0.1.2 --dry-run    # Validate only
#   ./release.sh 0.1.2 --no-upload  # Build locally without upload
#   ./release.sh 0.1.2 --no-tag     # Skip git tag creation
#   ./release.sh 0.1.2 --arch arm64 # Build for specific architecture only

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SelectionBar"
EXECUTABLE_NAME="SelectionBarApp"
INFO_PLIST="$SCRIPT_DIR/Info.plist"
RELEASES_DIR="$SCRIPT_DIR/releases"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Documents/Sparkle-2.8.1/bin}"

# GitHub configuration (same repo for code and releases)
GITHUB_REPO="tacshi/SelectionBar"

# Flags
DRY_RUN=false
NO_UPLOAD=false
NO_TAG=false
VERSION=""
ARCH=""
BUILD_ALL_ARCHS=true  # Default to building all architectures for releases

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-upload)
            NO_UPLOAD=true
            shift
            ;;
        --no-tag)
            NO_TAG=true
            shift
            ;;
        --arch)
            ARCH="$2"
            BUILD_ALL_ARCHS=false
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 VERSION [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run       Validate prerequisites without making changes"
            echo "  --no-upload     Build locally without uploading to GitHub"
            echo "  --no-tag        Skip git tag creation"
            echo "  --arch ARCH     Build for specific architecture only (arm64 or x86_64)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 0.1.2              # Full release (all architectures)"
            echo "  $0 0.1.2 --dry-run    # Validate only"
            echo "  $0 0.1.2 --no-upload  # Build without upload"
            echo "  $0 0.1.2 --arch arm64 # Build ARM64 only"
            exit 0
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Helper functions
log_step() {
    echo "" >&2
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BLUE}  $1${NC}" >&2
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

log_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

log_info() {
    echo -e "  $1" >&2
}

# Generate release notes from git log
generate_release_notes() {
    local prev_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    local notes=""

    if [[ -n "$prev_tag" ]]; then
        # Get commits since last tag, filtering out noise
        notes=$(git log "$prev_tag"..HEAD --pretty=format:"- %s" --no-merges 2>/dev/null | \
            grep -v "^- Bump version" | \
            grep -v "^- Merge " | \
            grep -v "^- v[0-9]" | \
            grep -v "^- Update appcast" | \
            grep -v "^- Release " | \
            head -20)
    else
        # No previous tag, get recent commits
        notes=$(git log --pretty=format:"- %s" --no-merges -20 2>/dev/null | \
            grep -v "^- Bump version" | \
            grep -v "^- Merge " | \
            grep -v "^- v[0-9]" | \
            grep -v "^- Update appcast" | \
            grep -v "^- Release " | \
            head -20)
    fi

    if [[ -z "$notes" ]]; then
        notes="- Bug fixes and improvements"
    fi

    echo "$notes"
}

# Escape HTML entities and convert markdown list to HTML list items
# Prevents XSS from malicious commit messages
escape_release_notes_html() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/^- /<li>/; s/$/<\/li>/'
}

# Build app for specific architecture
build_for_arch() {
    local arch="$1"
    local output_suffix="$2"

    log_info "Building for $arch..."
    swift build -c release --product "$EXECUTABLE_NAME" --arch "$arch" >&2

    local build_dir="$SCRIPT_DIR/.build/${arch}-apple-macosx/release"
    local app_dir="$SCRIPT_DIR/$APP_NAME-${output_suffix}.app"

    # Verify build succeeded
    if [[ ! -x "$build_dir/$EXECUTABLE_NAME" ]]; then
        log_error "Build failed for $arch: binary not found at $build_dir/$EXECUTABLE_NAME"
        exit 1
    fi

    create_app_bundle "$build_dir" "$app_dir" >&2

    # Sign
    sign_app_bundle "$app_dir" >&2

    # Create DMG
    local dmg_name="$APP_NAME-$VERSION-${output_suffix}.dmg"
    local dmg_path="$RELEASES_DIR/$dmg_name"
    create_dmg "$app_dir" "$dmg_path" "$APP_NAME"

    echo "$dmg_path"
}

# Build universal binary
build_universal() {
    log_info "Building universal binary (arm64 + x86_64)..."

    swift build -c release --product "$EXECUTABLE_NAME" --arch arm64 >&2
    swift build -c release --product "$EXECUTABLE_NAME" --arch x86_64 >&2

    local arm64_binary="$SCRIPT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
    local x86_64_binary="$SCRIPT_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE_NAME"

    if [[ ! -f "$arm64_binary" ]] || [[ ! -f "$x86_64_binary" ]]; then
        log_error "Failed to build both architectures"
        exit 1
    fi

    mkdir -p "$SCRIPT_DIR/.build/release"
    lipo -create "$arm64_binary" "$x86_64_binary" -output "$SCRIPT_DIR/.build/release/$EXECUTABLE_NAME" >&2

    # Copy resource bundles from one of the arch builds (they are the same)
    for bundle in "$SCRIPT_DIR/.build/arm64-apple-macosx/release"/*.bundle; do
        if [[ -d "$bundle" ]]; then
            cp -r "$bundle" "$SCRIPT_DIR/.build/release/"
        fi
    done

    local build_dir="$SCRIPT_DIR/.build/release"
    local app_dir="$SCRIPT_DIR/$APP_NAME.app"

    create_app_bundle "$build_dir" "$app_dir" >&2
    sign_app_bundle "$app_dir" >&2

    # Create DMG
    local dmg_name="$APP_NAME-$VERSION.dmg"
    local dmg_path="$RELEASES_DIR/$dmg_name"
    create_dmg "$app_dir" "$dmg_path" "$APP_NAME"

    echo "$dmg_path"
}

# Create app bundle from build directory
create_app_bundle() {
    local build_dir="$1"
    local app_dir="$2"

    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/"{MacOS,Resources,Frameworks}

    # Copy main executable (SPM builds as "SelectionBarApp", rename to "SelectionBar" in bundle)
    cp "$build_dir/$EXECUTABLE_NAME" "$app_dir/Contents/MacOS/$APP_NAME"

    # Fix rpaths on the renamed binary
    local binary_path="$app_dir/Contents/MacOS/$APP_NAME"
    install_name_tool -delete_rpath "/usr/lib/swift" "$binary_path" 2>/dev/null || true
    install_name_tool -delete_rpath "@loader_path" "$binary_path" 2>/dev/null || true
    for rpath in $(otool -l "$binary_path" | grep -A2 LC_RPATH | grep "path /Applications/Xcode" | awk '{print $2}'); do
        install_name_tool -delete_rpath "$rpath" "$binary_path" 2>/dev/null || true
    done
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$binary_path" 2>/dev/null || true

    # Copy Sparkle framework from build artifacts
    for sparkle_path in \
        "$build_dir/Sparkle.framework" \
        "$build_dir/Sparkle_Sparkle.framework" \
        "$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
        if [[ -d "$sparkle_path" ]]; then
            cp -R "$sparkle_path" "$app_dir/Contents/Frameworks/"
            break
        fi
    done

    # Copy Info.plist
    cp "$SCRIPT_DIR/Info.plist" "$app_dir/Contents/"

    # Copy resource bundles
    for bundle in "$build_dir"/*.bundle; do
        if [[ -d "$bundle" ]]; then
            cp -r "$bundle" "$app_dir/Contents/Resources/"
            chmod -R u+w "$app_dir/Contents/Resources/$(basename "$bundle")"
        fi
    done

    # App icon: copy from pre-generated assets
    local icon_icns_source="$SCRIPT_DIR/Assets/AppIcon.icns"
    local iconset_source="$SCRIPT_DIR/Assets/AppIcon.iconset"
    if [[ -f "$icon_icns_source" ]]; then
        cp "$icon_icns_source" "$app_dir/Contents/Resources/AppIcon.icns"
    elif [[ -d "$iconset_source" ]]; then
        iconutil -c icns "$iconset_source" -o "$app_dir/Contents/Resources/AppIcon.icns"
    else
        log_warning "Icon assets not found at Assets/AppIcon.icns or Assets/AppIcon.iconset"
    fi

    # Create PkgInfo
    echo -n "APPL????" > "$app_dir/Contents/PkgInfo"
}

# Sign app bundle with Developer ID
sign_app_bundle() {
    local app_dir="$1"

    # Sign Sparkle framework components
    local sparkle_framework="$app_dir/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$sparkle_framework" ]]; then
        for xpc in "$sparkle_framework/Versions/B/XPCServices"/*.xpc; do
            [[ -d "$xpc" ]] && codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$xpc"
        done
        for app in "$sparkle_framework/Versions/B"/*.app; do
            [[ -d "$app" ]] && codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$app"
        done
        for exe in "$sparkle_framework/Versions/B/Autoupdate"; do
            [[ -f "$exe" ]] && codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$exe"
        done
        codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$sparkle_framework"
    fi

    # Sign other frameworks
    for framework in "$app_dir/Contents/Frameworks"/*.framework; do
        if [[ -d "$framework" ]] && [[ "$(basename "$framework")" != "Sparkle.framework" ]]; then
            codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$framework"
        fi
    done

    # Sign main app with entitlements
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
        --entitlements "$SCRIPT_DIR/SelectionBar.entitlements" \
        --options runtime \
        --timestamp \
        "$app_dir"
}

# Create DMG from app bundle
create_dmg() {
    local app_dir="$1"
    local dmg_path="$2"
    local volume_name="$3"

    log_info "Creating DMG: $(basename "$dmg_path")..."

    # Remove existing DMG if present
    rm -f "$dmg_path"

    # Create temporary directory for DMG contents
    local dmg_temp="$SCRIPT_DIR/.build/dmg-temp"
    rm -rf "$dmg_temp"
    mkdir -p "$dmg_temp"

    # Copy app to temp directory
    cp -R "$app_dir" "$dmg_temp/"

    # Create symbolic link to Applications folder
    ln -s /Applications "$dmg_temp/Applications"

    # Create DMG
    hdiutil create -volname "$volume_name" \
        -srcfolder "$dmg_temp" \
        -ov -format UDZO \
        "$dmg_path" >&2

    # Cleanup temp directory
    rm -rf "$dmg_temp"

    log_success "Created $(basename "$dmg_path")"
}

# Notarize DMG
notarize_dmg() {
    local dmg_path="$1"

    log_info "Submitting to Apple for notarization..."
    local notarize_output=$(xcrun notarytool submit "$dmg_path" \
        --keychain-profile "SelectionBar" \
        --wait 2>&1)

    echo "$notarize_output"

    if echo "$notarize_output" | grep -q "status: Accepted"; then
        log_success "Notarization accepted"

        # Staple ticket directly to DMG
        log_info "Stapling notarization ticket to DMG..."
        xcrun stapler staple "$dmg_path"
        log_success "Ticket stapled to DMG"
    else
        log_error "Notarization failed"
        exit 1
    fi
}

# ============================================================================
# STEP 1: VALIDATE
# ============================================================================
log_step "1. Validating prerequisites"

# Check version argument
if [[ -z "$VERSION" ]]; then
    log_error "Version argument required"
    echo "Usage: $0 VERSION [OPTIONS]"
    echo "Example: $0 0.1.2"
    exit 1
fi

# Validate semver format (allows pre-release suffixes like -rc.1)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+(\.[0-9]+)?)?$ ]]; then
    log_error "Invalid version format: $VERSION"
    exit 1
fi
log_success "Version format valid: $VERSION"

# Check DEVELOPER_ID_APPLICATION
if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
    log_error "DEVELOPER_ID_APPLICATION environment variable not set"
    log_info "Set it with: export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi
log_success "Developer ID found"

# Check notarytool credentials
if ! xcrun notarytool history --keychain-profile "SelectionBar" > /dev/null 2>&1; then
    log_error "Notarization credentials not found for keychain profile 'SelectionBar'"
    log_info "Store credentials with: xcrun notarytool store-credentials \"SelectionBar\" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID"
    exit 1
fi
log_success "Notarization credentials found"

# Check Sparkle tools
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    log_warning "Sparkle tools not found at $SPARKLE_BIN"
    log_info "Attempting build to resolve SPM artifacts..."
    swift build -c release --product "$EXECUTABLE_NAME" 2>/dev/null || true
    # Verify tools are now available
    if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
        log_error "Sparkle tools still not found at $SPARKLE_BIN after build"
        log_info "Set SPARKLE_BIN to the directory containing generate_appcast and sign_update"
        exit 1
    fi
fi
log_success "Sparkle tools available"

# Check gh CLI for GitHub releases
if [[ "$NO_UPLOAD" == "false" ]]; then
    if ! command -v gh &> /dev/null; then
        log_error "gh CLI not found (required for GitHub releases)"
        echo "Install with: brew install gh"
        exit 1
    fi
    if ! gh auth status &> /dev/null; then
        log_error "gh not authenticated. Run: gh auth login"
        exit 1
    fi
    log_success "GitHub CLI configured"
fi

# Check Info.plist
if [[ ! -f "$INFO_PLIST" ]]; then
    log_error "Info.plist not found at $INFO_PLIST"
    exit 1
fi
log_success "Info.plist found"

# Get current version info
CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
CURRENT_BUILD=$(plutil -extract CFBundleVersion raw "$INFO_PLIST")
NEW_BUILD=$((CURRENT_BUILD + 1))

log_info "Current: $CURRENT_VERSION (build $CURRENT_BUILD)"
log_info "New: $VERSION (build $NEW_BUILD)"

# Generate release notes preview
RELEASE_NOTES=$(generate_release_notes)
log_info "Release notes preview:"
echo "$RELEASE_NOTES" | head -5 | while read line; do
    log_info "  $line"
done

# Dry run stops here
if [[ "$DRY_RUN" == "true" ]]; then
    log_step "DRY RUN COMPLETE"
    log_success "All prerequisites validated"
    exit 0
fi

# ============================================================================
# STEP 2: VERSION BUMP
# ============================================================================
log_step "2. Updating version in Info.plist"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
log_success "CFBundleShortVersionString → $VERSION"

plutil -replace CFBundleVersion -string "$NEW_BUILD" "$INFO_PLIST"
log_success "CFBundleVersion → $NEW_BUILD"

# Commit version bump (only if there are changes)
log_info "Committing version bump..."
git add "$INFO_PLIST"
if ! git diff --cached --quiet -- "$INFO_PLIST"; then
    git commit -m "Bump version to $VERSION (build $NEW_BUILD)"
    log_success "Committed version changes"
else
    log_info "No changes to commit (version already set)"
fi

# ============================================================================
# STEP 3: BUILD
# ============================================================================
log_step "3. Building $APP_NAME"

cd "$SCRIPT_DIR"
mkdir -p "$RELEASES_DIR"

# Format code
log_info "Formatting Swift code..."
swift-format --recursive --in-place . 2>/dev/null || true

# Declare arrays for archives
declare -a ARCHIVE_PATHS
declare -a ARCHIVE_NAMES

if [[ "$BUILD_ALL_ARCHS" == "true" ]]; then
    # Build all three variants
    log_info "Building all architecture variants..."

    # ARM64
    ARCHIVE_ARM64=$(build_for_arch "arm64" "arm64")
    ARCHIVE_PATHS+=("$ARCHIVE_ARM64")
    ARCHIVE_NAMES+=("$(basename "$ARCHIVE_ARM64")")

    # x86_64
    ARCHIVE_X86=$(build_for_arch "x86_64" "intel")
    ARCHIVE_PATHS+=("$ARCHIVE_X86")
    ARCHIVE_NAMES+=("$(basename "$ARCHIVE_X86")")

    # Universal
    ARCHIVE_UNIVERSAL=$(build_universal)
    ARCHIVE_PATHS+=("$ARCHIVE_UNIVERSAL")
    ARCHIVE_NAMES+=("$(basename "$ARCHIVE_UNIVERSAL")")

    # Use universal as the primary app for notarization
    PRIMARY_APP="$SCRIPT_DIR/$APP_NAME.app"
    PRIMARY_ARCHIVE="$ARCHIVE_UNIVERSAL"
else
    # Build single architecture
    if [[ -n "$ARCH" ]]; then
        ARCHIVE_PATH=$(build_for_arch "$ARCH" "$ARCH")
        PRIMARY_APP="$SCRIPT_DIR/$APP_NAME-${ARCH}.app"
    else
        ARCHIVE_PATH=$(build_universal)
        PRIMARY_APP="$SCRIPT_DIR/$APP_NAME.app"
    fi
    ARCHIVE_PATHS+=("$ARCHIVE_PATH")
    ARCHIVE_NAMES+=("$(basename "$ARCHIVE_PATH")")
    PRIMARY_ARCHIVE="$ARCHIVE_PATH"
fi

log_success "All builds complete"

# ============================================================================
# STEP 4: NOTARIZE
# ============================================================================
log_step "4. Notarizing with Apple"

# Notarize the primary (universal) build
notarize_dmg "$PRIMARY_ARCHIVE"

# If building all archs, notarize the arch-specific builds too
if [[ "$BUILD_ALL_ARCHS" == "true" ]]; then
    log_info "Notarizing architecture-specific builds..."

    # ARM64
    notarize_dmg "$ARCHIVE_ARM64"

    # x86_64
    notarize_dmg "$ARCHIVE_X86"
fi

log_success "All builds notarized"

# ============================================================================
# STEP 5: GENERATE APPCAST
# ============================================================================
log_step "5. Generating appcast with release notes"

# Move old version DMGs and arch-specific builds out temporarily
# Sparkle only supports one archive per version, and old versions cause conflicts
TEMP_ARCH_DIR="$SCRIPT_DIR/.build/arch-releases"
rm -rf "$TEMP_ARCH_DIR"
mkdir -p "$TEMP_ARCH_DIR"

# Keep only the primary archive (handles both universal and arch-specific builds)
PRIMARY_DMG_NAME=$(basename "$PRIMARY_ARCHIVE")
for dmg in "$RELEASES_DIR"/*.dmg; do
    [[ -f "$dmg" ]] || continue
    dmg_name=$(basename "$dmg")
    # Keep only the primary DMG for appcast generation
    if [[ "$dmg_name" != "$PRIMARY_DMG_NAME" ]]; then
        mv "$dmg" "$TEMP_ARCH_DIR/"
    fi
done
log_info "Isolated primary build ($PRIMARY_DMG_NAME) for appcast generation"

# Run generate_appcast with only the primary DMG (universal or arch-specific) in directory
"$SPARKLE_BIN/generate_appcast" "$RELEASES_DIR"
log_success "Appcast generated"

# Add embedded release notes as inline CDATA so Sparkle renders HTML directly
# without a network fetch (raw.githubusercontent.com serves text/plain which
# causes Sparkle's WKWebView to display raw HTML source).
log_info "Embedding release notes in appcast..."
ESCAPED_DESCRIPTION_NOTES=$(escape_release_notes_html "$RELEASE_NOTES")
DESCRIPTION_BLOCK="            <description><![CDATA[<h2>What's New in $VERSION</h2><ul>$(echo "$ESCAPED_DESCRIPTION_NOTES" | tr -d '\n')</ul>]]></description>"
# Insert description after minimumSystemVersion for this version's item block
sed -i '' "/<title>$VERSION<\/title>/,/<enclosure/{
    /<sparkle:minimumSystemVersion/a\\
$DESCRIPTION_BLOCK
}" "$RELEASES_DIR/appcast.xml"
# Remove any releaseNotesLink lines as a safety measure
sed -i '' '/<sparkle:releaseNotesLink/d' "$RELEASES_DIR/appcast.xml"
# Add fullReleaseNotesLink so Sparkle's "Version History" button works
FULL_NOTES_LINK="        <sparkle:fullReleaseNotesLink>https://github.com/$GITHUB_REPO/releases</sparkle:fullReleaseNotesLink>"
if ! grep -q 'fullReleaseNotesLink' "$RELEASES_DIR/appcast.xml"; then
    sed -i '' "/<title>$APP_NAME<\/title>/a\\
$FULL_NOTES_LINK
" "$RELEASES_DIR/appcast.xml"
fi
log_success "Release notes embedded in appcast"

# Move current version's arch-specific builds back for GitHub upload
if [[ "$BUILD_ALL_ARCHS" == "true" ]]; then
    mv "$TEMP_ARCH_DIR/$APP_NAME-$VERSION-arm64.dmg" "$RELEASES_DIR/" 2>/dev/null || true
    mv "$TEMP_ARCH_DIR/$APP_NAME-$VERSION-intel.dmg" "$RELEASES_DIR/" 2>/dev/null || true
fi
# Note: Old version DMGs stay in temp dir (will be cleaned on next release)

# ============================================================================
# STEP 6: UPLOAD TO GITHUB
# ============================================================================
if [[ "$NO_UPLOAD" == "true" ]]; then
    log_step "6. Upload skipped (--no-upload)"
else
    log_step "6. Creating GitHub Release"

    TAG_NAME="v$VERSION"

    # Create git tag if needed
    if [[ "$NO_TAG" == "false" ]]; then
        if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
            git tag -a "$TAG_NAME" -m "Release $VERSION"
            log_success "Created git tag: $TAG_NAME"
        fi
    fi

    # Create release notes markdown
    RELEASE_BODY=$(cat << EOF
## What's New

$RELEASE_NOTES

## Downloads

| Platform | Download |
|----------|----------|
| Universal (Recommended) | \`$APP_NAME-$VERSION.dmg\` |
| Apple Silicon (arm64) | \`$APP_NAME-$VERSION-arm64.dmg\` |
| Intel (x86_64) | \`$APP_NAME-$VERSION-intel.dmg\` |

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon recommended for best performance
EOF
)

    # Create GitHub release with DMGs
    log_info "Creating GitHub release..."
    gh release create "$TAG_NAME" \
        --repo "$GITHUB_REPO" \
        --title "$APP_NAME $VERSION" \
        --notes "$RELEASE_BODY" \
        "${ARCHIVE_PATHS[@]}"

    log_success "GitHub release created"

    # Update appcast download URL for this version only (not older entries)
    log_info "Updating appcast URLs..."
    GITHUB_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG_NAME"
    sed -i '' "/<title>$VERSION<\/title>/,/<\/item>/{
        s|url=\"[^\"]*/$APP_NAME-|url=\"$GITHUB_DOWNLOAD_URL/$APP_NAME-|
    }" "$RELEASES_DIR/appcast.xml"
    log_success "Appcast URLs updated to point to GitHub releases"

    # Commit appcast and release notes to the same repo
    log_info "Committing appcast to repository..."
    cd "$SCRIPT_DIR"
    git add "releases/appcast.xml"
    git commit -m "Update appcast for $VERSION"
    log_success "Appcast committed"

    # Show release URL
    RELEASE_URL="https://github.com/$GITHUB_REPO/releases/tag/$TAG_NAME"
    log_success "Release published: $RELEASE_URL"
fi

# ============================================================================
# STEP 7: CLEANUP & SUMMARY
# ============================================================================
log_step "7. Finishing up"

# Push version commit, appcast commit, and git tag
if [[ "$NO_UPLOAD" == "false" ]]; then
    log_info "Pushing changes to origin..."
    git push origin HEAD 2>/dev/null || log_warning "Push failed (may need manual push)"
    if [[ "$NO_TAG" == "false" ]]; then
        git push origin "$TAG_NAME" 2>/dev/null || log_warning "Tag already pushed or push failed"
    fi
    log_success "Changes pushed to origin"
fi

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Release $VERSION Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Version: $VERSION (build $NEW_BUILD)"
echo ""
echo "  Archives:"
for name in "${ARCHIVE_NAMES[@]}"; do
    echo "    - $name"
done
echo ""

if [[ "$NO_UPLOAD" == "false" ]]; then
    echo "  Published to:"
    echo "    https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
    echo ""
    echo "  Appcast URL:"
    echo "    https://raw.githubusercontent.com/$GITHUB_REPO/main/releases/appcast.xml"
    echo ""
fi

echo "  Next step:"
echo "    - Test update from previous version"
echo ""
