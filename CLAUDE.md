# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SelectionBar is a macOS menu bar app (Swift 6.0, macOS 14+) that provides a floating toolbar on text selection for quick actions like search, translate, lookup, and custom LLM/JavaScript processing.

## Build Commands

```bash
# SPM build (fast iteration)
swift build

# Debug app bundle
./scripts/build-debug.sh

# Skip formatting / signing
./scripts/build-debug.sh --no-format --no-sign

# Run all tests
swift test

# Run a single test by name
swift test --filter SelectionBarCoreTests.testName

# Format code (also run automatically by build-debug.sh)
# Use xcrun so this matches the toolchain formatter CI runs — a Homebrew
# swift-format can be a different version and disagree.
xcrun swift-format --recursive --in-place Sources Tests Package.swift
```

## Architecture

Four-target SPM package — no Xcode project files:

- **SelectionBarApp** (executable) — SwiftUI menu bar app, settings UI, provider configuration. Depends on SelectionBarCore and Sparkle.
- **SelectionBarCore** (library) — Selection monitoring, action execution, floating toolbar, settings persistence. Depends on SelectionBarJavaScriptEngine.
- **SelectionBarJavaScriptEngine** (library) — JavaScriptCore execution plus the helper wire protocol. No external dependencies.
- **SelectionBarJSHelper** (executable) — One-shot child process: reads a request on stdin, runs one script, writes the response to stdout, exits. Embedded at `Contents/Helpers/selectionbar-js-helper` by the build scripts.

JavaScript actions go through `SelectionBarJavaScriptExecutor`, which spawns the helper and enforces a hard deadline (JavaScriptCore cannot be interrupted from Swift, so the timeout has to be a process kill). It falls back to the in-process `SelectionBarJavaScriptRunner` when the helper is absent — which is the case under `swift build`/`swift test`.

### Data Flow

`SelectionMonitor` (Accessibility API) → `SelectionBarCoordinator` (lifecycle) → `SelectionBarView` (floating toolbar) → `SelectionBarActionHandler` (execution) → `SelectionResultView` or inline edit

### Key Patterns

- **State:** `@Observable` with `@MainActor` throughout. `SelectionBarSettingsStore` persists to UserDefaults; API keys go to Keychain via `KeychainHelper`.
- **Actions:** Two kinds — JavaScript (JavaScriptCore, `transform(input)` entry point) and LLM (OpenAI-compatible API). Two output modes — result window or inplace edit.
- **Providers:** OpenAI, OpenRouter, DeepL, ElevenLabs, plus user-defined OpenAI-compatible endpoints via `CustomLLMProvider`.
- **Settings lifecycle:** `didSet` hooks on store properties trigger callbacks (`onEnabledChanged`, `onIgnoredAppsChanged`, etc.) that the coordinator observes.
- **Tests:** Swift Testing framework (not XCTest). Test helpers in `Tests/SelectionBarCoreTests/Support/TestDoubles.swift` — `InMemoryKeychain`, isolated UserDefaults suites per test.
- **Settings persistence is coalesced.** `didSet` schedules a save ~250ms later rather than writing immediately. Tests that construct a second store to read values back must call `store.flushPendingWrites()` first; the app flushes on `applicationWillTerminate`.

## CI

`.github/workflows/ci.yml` runs `xcrun swift-format lint --strict`, `swift build`, and `swift test` on every push to main and every PR. Run all three locally before pushing.

`swift-format` is not on `PATH` on the GitHub runners; it ships inside the Swift toolchain, so CI invokes it through `xcrun`. The workflow deliberately does not pin an Xcode path — runner images use versioned bundle names (`Xcode_16.4.app`) that change without notice.

### Localization

Three languages: English (en), Japanese (ja), Simplified Chinese (zh-Hans). Strings live in `Localizable.xcstrings` files under each target's Resources/.

## Release

```bash
./scripts/build-release.sh 0.4.0              # Full release (build, sign, upload, tag)
./scripts/build-release.sh 0.4.0 --dry-run    # Validate without side effects
```

Releases go to GitHub (`tacshi/SelectionBar`) with Sparkle appcast generation. Artifacts land in `releases/`.
