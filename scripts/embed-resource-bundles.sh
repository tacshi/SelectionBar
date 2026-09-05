#!/bin/bash
# Copy resource bundles into a macOS app before signing it.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 BUILD_DIR APP_BUNDLE" >&2
  exit 1
fi

build_dir="$1"
app_dir="$2"
mkdir -p "$app_dir/Contents/Resources"

found_bundle=false
for bundle in "$build_dir"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  found_bundle=true
  bundle_name="$(basename "$bundle")"
  cp -R "$bundle" "$app_dir/Contents/Resources/"
  chmod -R u+w "$app_dir/Contents/Resources/$bundle_name"
done

if [[ "$found_bundle" == false ]]; then
  echo "No SwiftPM resource bundles found in $build_dir" >&2
  exit 1
fi
