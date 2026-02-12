# SelectionBar

A macOS menu bar app that provides instant text processing, translation, lookup, and web search through a floating toolbar that appears on text selection.

## Features

### Quick Actions

- **Copy** - Copy selected text to clipboard
- **Cut** - Cut selected text to clipboard
- **Open URL** - Open selected text as a URL in the default browser

### Web Search

Search selected text with 7 built-in engines:

- Google, Bing, DuckDuckGo, Baidu, Sogou, 360 Search, Yandex

### Word Lookup

- **System Dictionary** - macOS built-in dictionary
- **Eudic** - Launch Eudic with the selected word
- **Custom App** - Open any dictionary app via URL scheme

### Translation

- **App-based** - Bob (via AppleScript), Eudic (via URL scheme)
- **LLM-based** - Translate using any configured LLM provider with 27 target languages including English, Chinese (Simplified/Traditional), Japanese, Korean, Spanish, French, German, Italian, Portuguese, Russian, Arabic, Hindi, Vietnamese, Thai, Dutch, Polish, Turkish, Ukrainian, Czech, Swedish, Danish, Finnish, Greek, Hebrew, Indonesian, and Malay

### Custom LLM Actions

6 built-in prompt templates, plus support for creating your own:

- Polish, Clean Up, Extract Actions, Summarize, Bulletize, Draft Email

### Custom JavaScript Actions

8 starter templates with offline, instant execution:

- Trim Whitespace, Title Case, URL Toolkit, JWT Decode, Format JSON, Convert Timestamps, Clean Up Escapes, Wrap as Quote

### Do Not Disturb

Require a modifier key (Option, Command, Control, or Shift) to activate the toolbar. Prevents the toolbar from appearing during normal text selection.

### Ignored Apps

Exclude specific applications from text selection monitoring.

### Auto-Updates

Built-in update checking via Sparkle.

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (for global text selection monitoring)

## Installation

### Build from Source

```bash
git clone https://github.com/tacshi/SelectionBar.git
cd SelectionBar
./build-app.sh
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

## Supported Providers

| Provider | Type | Setup |
|----------|------|-------|
| OpenAI | LLM + Translation | API key required |
| OpenRouter | LLM + Translation | API key required |
| DeepL | Translation | API key required |
| Custom | LLM and/or Translation | OpenAI-compatible endpoint |

## Architecture

SelectionBar uses a two-layer architecture:

- **SelectionBarApp** - SwiftUI menu bar app, settings UI, provider configuration
- **SelectionBarCore** - Core library with selection monitoring, action handling, floating toolbar

### Data Flow

1. `SelectionMonitor` detects text selection via Accessibility API
2. `SelectionBarCoordinator` shows the floating `SelectionBarView`
3. User clicks an action and `SelectionBarActionHandler` processes it
4. Results are displayed in `SelectionResultView` or replaced inline

## Tech Stack

- Swift 6.0 / SwiftUI
- `@Observable` (Observation framework)
- macOS Accessibility APIs
- JavaScriptCore (custom JS actions)
- Sparkle (auto-updates)
- Keychain Services (secure credential storage)

## License

MIT License
