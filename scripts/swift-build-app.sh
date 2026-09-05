#!/bin/bash
# Xcode's SwiftPM integration generates Bundle.module accessors that search
# Contents/Resources in a macOS .app, including for third-party dependencies.
# The native build system instead searches the app root and the build directory.
set -euo pipefail

exec swift build --build-system xcode "$@"
