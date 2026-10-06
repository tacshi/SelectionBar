#!/bin/bash
# Swift Build generates Bundle.module accessors that search Contents/Resources.
# Keep the Xcode backend for older toolchains that lack Swift Build support.
set -euo pipefail

build_help="$(swift build --help)"
if [[ "$build_help" == *swiftbuild* ]]; then
  exec swift build --build-system swiftbuild "$@"
fi

exec swift build --build-system xcode "$@"
