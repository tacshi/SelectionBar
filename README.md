# SelectionBar

A macOS menu bar app that provides a floating toolbar on text selection for quick actions — copy, search, translate, speak, chat with AI, and run custom LLM/JavaScript processing.

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

6 built-in prompt templates, plus support for creating your own:

- Polish, Clean Up, Extract Actions, Summarize, Bulletize, Draft Email

Each action can output to a result window or edit text inline.

### Custom JavaScript Actions

8 starter templates with offline, instant execution:

- Trim Whitespace, Title Case, URL Toolkit, JWT Decode, Format JSON, Convert Timestamps, Clean Up Escapes, Wrap as Quote

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

| Provider | Capabilities | Setup |
|----------|-------------|-------|
| OpenAI | LLM, Translation, Chat | API key required |
| OpenRouter | LLM, Translation, Chat | API key required |
| DeepL | Translation | API key required |
| ElevenLabs | Text-to-Speech | API key required |
| Custom | LLM, Translation, and/or TTS | OpenAI-compatible endpoint |

## Architecture

Two-target SPM package:

- **SelectionBarApp** - SwiftUI menu bar app, settings UI, provider configuration
- **SelectionBarCore** - Core library with selection monitoring, action handling, floating toolbar, chat

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

## License

MIT License
