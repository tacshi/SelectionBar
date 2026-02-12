# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SelectionBar is a macOS menu bar app (Swift 6.0, macOS 14+) that provides a floating toolbar on text selection for quick actions like search, translate, lookup, and custom LLM/JavaScript processing.

## Build Commands

```bash
# SPM build (fast iteration)
swift build

# Full app bundle (release, signed, formatted)
./build-app.sh

# Debug app bundle
./build-app.sh --debug

# Skip formatting / signing
./build-app.sh --no-format --no-sign

# Run all tests
swift test

# Run a single test by name
swift test --filter SelectionBarCoreTests.testName

# Format code (also run automatically by build-app.sh)
swift-format --recursive --in-place Sources Tests Package.swift
```

## Architecture

Two-target SPM package — no Xcode project files:

- **SelectionBarApp** (executable) — SwiftUI menu bar app, settings UI, provider configuration. Depends on SelectionBarCore and Sparkle.
- **SelectionBarCore** (library) — Selection monitoring, action execution, floating toolbar, settings persistence. No external dependencies.

### Data Flow

`SelectionMonitor` (Accessibility API) → `SelectionBarCoordinator` (lifecycle) → `SelectionBarView` (floating toolbar) → `SelectionBarActionHandler` (execution) → `SelectionResultView` or inline edit

### Key Patterns

- **State:** `@Observable` with `@MainActor` throughout. `SelectionBarSettingsStore` persists to UserDefaults; API keys go to Keychain via `KeychainHelper`.
- **Actions:** Two kinds — JavaScript (JavaScriptCore, `transform(input)` entry point) and LLM (OpenAI-compatible API). Two output modes — result window or inplace edit.
- **Providers:** OpenAI, OpenRouter, DeepL, ElevenLabs, plus user-defined OpenAI-compatible endpoints via `CustomLLMProvider`.
- **Settings lifecycle:** `didSet` hooks on store properties trigger callbacks (`onEnabledChanged`, `onIgnoredAppsChanged`, etc.) that the coordinator observes.
- **Tests:** Swift Testing framework (not XCTest). Test helpers in `Tests/SelectionBarCoreTests/Support/TestDoubles.swift` — `InMemoryKeychain`, isolated UserDefaults suites per test.

### Localization

Three languages: English (en), Japanese (ja), Simplified Chinese (zh-Hans). Strings live in `Localizable.xcstrings` files under each target's Resources/.

## Release

```bash
./release.sh 0.4.0              # Full release (build, sign, upload, tag)
./release.sh 0.4.0 --dry-run    # Validate without side effects
```

Releases go to GitHub (`tacshi/SelectionBar`) with Sparkle appcast generation. Artifacts land in `releases/`.
