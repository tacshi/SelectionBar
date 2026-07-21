# SelectionBar

[![CI](https://github.com/tacshi/SelectionBar/actions/workflows/ci.yml/badge.svg)](https://github.com/tacshi/SelectionBar/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/tacshi/SelectionBar/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A macOS menu bar app that provides a floating toolbar on text selection for quick actions — copy, search, translate, speak, chat with AI, and run custom LLM/JavaScript/key-binding actions.

## Features

### Quick Actions

- **Copy** / **Cut** - Clipboard operations on selected text
- **Open URL** - Open selected text as a URL in the default browser

### Web Search

Search selected text with 7 built-in engines:

- Google, Bing, DuckDuckGo, Baidu, Sogou, 360 Search, Yandex
- Custom URL scheme or URL template using `{{query}}` (for example `myapp` or `https://example.com/search?q={{query}}`)

### Word Lookup

- **System Dictionary** - macOS built-in dictionary
- **Eudic** - Launch Eudic with the selected word
- **Custom App** - Open any dictionary app via URL scheme

### Translation

- **App-based** - Bob (via AppleScript), Eudic (via URL scheme)
- **LLM-based** - Translate using any configured LLM provider with 27 target languages including English, Chinese (Simplified/Traditional), Japanese, Korean, Spanish, French, German, and more
- **DeepL** - API-based translation

### Text-to-Speech

- **System** - Apple's built-in AVSpeechSynthesizer with multiple voices and languages
- **ElevenLabs** - High-quality API-based TTS with multiple models (v3, Turbo v2.5, Flash v2.5, Multilingual v2) and custom voice selection

### Chat

Chat with AI about selected text in a floating panel with streaming responses and rich Markdown rendering.

- Source context awareness — the AI can read the source file (line-range) or web page (character-range) for deeper understanding
- Supports PDF files via PDFKit text extraction
- Tool calling with user approval before reading source content
- Copy or apply AI responses directly to the original selection
- Pinnable panel that persists across interactions

### Custom LLM Actions

5 built-in prompt templates, plus support for creating your own:

- Polish, Extract Actions, Summarize, Bulletize, Draft Email

Each action can output to a result window or edit text inline. LLM actions can optionally include bounded source context from the current file, PDF, or web page using `{{CONTEXT}}`, `{{SOURCE_URL}}`, `{{APP_NAME}}`, and `{{BUNDLE_ID}}`.

### Custom JavaScript Actions

7 starter templates with JavaScriptCore execution, including async `fetch` support for HTTP/HTTPS requests:

- Title Case, URL Toolkit, JWT Decode, Format JSON, Convert Timestamps, Clean Up Escapes, Wrap as Quote

Scripts run in a separate helper process (`Contents/Helpers/selectionbar-js-helper`),
so a script that never terminates is killed at its deadline instead of tying up
SelectionBar. If the helper is missing, execution falls back to running in-process.

### Key Binding Actions

Create shortcut actions in **Actions > Built-in > Key Bindings** to trigger app commands directly (for example `cmd+b` for Bold).

- Add multiple shortcut actions with custom names and icons
- Configure per-app shortcut overrides by bundle ID
- Built-in starters: Bold, Italic, Underline

### Do Not Disturb

Require a modifier key (Option, Command, Control, or Shift) to activate the toolbar. Prevents the toolbar from appearing during normal text selection.

### Other

- **Ignored Apps** - Exclude specific applications from text selection monitoring
- **Launch at Login** - Auto-start SelectionBar on login
- **Auto-Updates** - Built-in update checking via Sparkle

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (for global text selection monitoring)
- Automation permission (optional, for browser page reading and app-specific integrations)

## Installation

### Download

Grab the latest signed build from the
[releases page](https://github.com/tacshi/SelectionBar/releases/latest), open the
DMG, and drag **SelectionBar.app** into `/Applications`. The app updates itself
via Sparkle after that.

### Build from Source

```bash
git clone https://github.com/tacshi/SelectionBar.git
cd SelectionBar
./scripts/build-debug.sh
open SelectionBar.app
```

## Usage

1. **Launch the app** - SelectionBar appears in the menu bar
2. **Grant Accessibility permission** when prompted
3. **Select any text** in any application
4. **A floating toolbar appears** with action buttons
5. **Click an action** to process the selected text

### Do Not Disturb Mode

Hold a configured modifier key while selecting text to activate the toolbar. When enabled, the toolbar will not appear unless the modifier key is held down.

## Troubleshooting

### The toolbar never appears

SelectionBar reads selections through the Accessibility API, so it needs
Accessibility permission — and macOS silently does nothing when that permission
is missing.

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Make sure **SelectionBar** is listed and toggled on.
3. If it is already on but nothing happens, toggle it off and on again — macOS
   invalidates the grant whenever the app binary changes, which happens on every
   update and on every local rebuild.
4. Quit and relaunch SelectionBar.

Check **Ignored Apps** in settings too: the toolbar is suppressed in any app
listed there, and in password fields (macOS blocks synthetic events while secure
input is active).

### The toolbar appears but shows no text in some apps

A few apps (Electron and Java-based ones especially) do not expose selections
through the Accessibility API. For those, add the app under **Clipboard Fallback**
in settings — SelectionBar will synthesize a copy and restore your clipboard
afterwards.

### AI actions fail with an HTTP error

Confirm the provider's API key is saved (**Providers** tab, use *Test
Connection*) and that the model ID is one your account can reach. For custom
OpenAI-compatible endpoints, the base URL must include the version path, e.g.
`https://example.com/v1`.

## Supported Providers

| Provider | Capabilities | Setup |
|----------|-------------|-------|
| OpenAI | LLM, Translation, Chat | API key required |
| OpenRouter | LLM, Translation, Chat | API key required |
| DeepL | Translation | API key required |
| ElevenLabs | Text-to-Speech | API key required |
| Custom | LLM, Translation, and/or TTS | OpenAI-compatible endpoint |

## Architecture

SPM package with four targets:

- **SelectionBarApp** - SwiftUI menu bar app, settings UI, provider configuration
- **SelectionBarCore** - Core library with selection monitoring, action handling, floating toolbar, chat
- **SelectionBarJavaScriptEngine** - JavaScriptCore execution engine, shared by the app and the helper
- **SelectionBarJSHelper** - One-shot child process that runs a single JavaScript action and exits

### Data Flow

1. `SelectionMonitor` detects text selection via Accessibility API
2. `SelectionBarCoordinator` shows the floating `SelectionBarView`
3. User clicks an action → `SelectionBarActionHandler` processes it
4. Results are displayed in `SelectionResultView`, replaced inline, or shown in `ChatPanelView`

## Tech Stack

- Swift 6.0 / SwiftUI
- `@Observable` (Observation framework)
- macOS Accessibility APIs
- JavaScriptCore (custom JS actions)
- MarkdownUI (chat response rendering)
- PDFKit (PDF text extraction)
- Sparkle (auto-updates)
- Keychain Services (secure credential storage)

## Localization

English, Japanese, Simplified Chinese.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

```bash
xcrun swift-format --recursive --in-place Sources Tests Package.swift
swift build
swift test
```

CI runs the same three steps on every pull request.

## License

[MIT](LICENSE)
