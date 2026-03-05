# VoiceLog

**One-Button Meeting Dictation + Notion Intelligence**

A lightweight macOS menu bar app that records meetings, transcribes them locally with OpenAI Whisper, generates AI summaries, and pushes structured notes to Notion — all with zero friction.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## How It Works

```
Record → Transcribe → Summarize → Sync to Notion
```

1. Click the menu bar icon or press `⌃⌥R` to start recording
2. Press again to stop — Whisper transcribes locally (no audio leaves your machine)
3. AI generates a summary, action items, and key decisions
4. Review and sync to your Notion database with one click

## Features

### Core Recording
- **Menu bar app** — always accessible, never in the way
- **One-button toggle** — click or global hotkey (`⌃⌥R`) to start/stop
- **Pause/resume** — mid-session pause without ending the recording
- **Recording timer** — live elapsed time in the menu bar
- **Audio device selection** — built-in mic, AirPods, external USB, or virtual drivers

### Local Transcription (Whisper)
- **Fully on-device** — no audio transmitted externally
- **Model selection** — tiny (~75 MB) to large (~2.9 GB) with speed/accuracy tradeoffs
- **Auto language detection** — with manual override for non-English meetings
- **Long recording support** — auto-chunks recordings >10 min for performance
- **Progress tracking** — visual progress bar during transcription

### AI Post-Processing
- **Meeting summary** — 3-5 sentence overview
- **Action items** — extracted with implied owners
- **Key decisions** — highlighted separately
- **Auto-suggested title** — editable before sync
- **Dual backend** — local via Ollama or cloud via OpenAI API

### Notion Integration
- **OAuth authentication** — no manual API key copy-paste
- **Database auto-creation** — creates a pre-configured Meeting Log database
- **Schema validation** — verifies your database has the right properties
- **Rich page structure** — summary callout, action item checklists, transcript toggle
- **Offline retry queue** — queues failed syncs and retries automatically
- **Exponential backoff** — handles rate limits gracefully

### Privacy First
- All audio processed on-device by default
- Transcripts stored locally in `~/Library/Application Support/VoiceLog/`
- OAuth tokens stored in macOS Keychain
- AI processing runs locally via Ollama unless you opt into OpenAI
- No telemetry or analytics

## Requirements

- macOS 13 Ventura or later (Apple Silicon + Intel)
- [Whisper](https://github.com/openai/whisper) (`pip install openai-whisper`) or [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [Ollama](https://ollama.ai) (optional, for local AI summaries)
- A [Notion](https://notion.so) account (for sync)

## Getting Started

### Build from Source

```bash
git clone https://github.com/benyetra/VoiceLog.git
cd VoiceLog
swift build
```

### Run Tests

```bash
swift test
```

### Install Whisper

```bash
# Python package (recommended)
pip install openai-whisper

# Or build whisper.cpp from source
# See: https://github.com/ggerganov/whisper.cpp
```

### Install Ollama (Optional)

```bash
# Download from https://ollama.ai
# Then pull a model:
ollama pull llama3
```

## Project Structure

```
VoiceLog/
├── Package.swift                    # Swift Package Manager config
├── Sources/VoiceLog/
│   ├── VoiceLogApp.swift            # App entry point (MenuBarExtra)
│   ├── Models/
│   │   ├── MeetingRecord.swift      # Core data model + enums
│   │   ├── AppState.swift           # Observable app state
│   │   └── Settings.swift           # Persistent user settings
│   ├── Services/
│   │   ├── AudioRecordingService.swift    # AVFoundation mic capture
│   │   ├── WhisperService.swift           # Whisper CLI integration
│   │   ├── AIPostProcessingService.swift  # Ollama / OpenAI summarization
│   │   ├── NotionService.swift            # Notion OAuth + API
│   │   ├── DatabaseService.swift          # SQLite via GRDB
│   │   ├── KeychainService.swift          # macOS Keychain wrapper
│   │   └── HotkeyService.swift           # Global hotkey (Carbon)
│   └── Views/
│       ├── MenuBarView.swift        # Main menu bar popover
│       ├── MeetingPreviewView.swift # Pre-sync review
│       ├── SettingsView.swift       # 6-tab preferences
│       └── OnboardingView.swift     # First-run setup wizard
└── Tests/VoiceLogTests/
    ├── MeetingRecordTests.swift
    ├── AppStateTests.swift
    ├── DatabaseServiceTests.swift
    ├── AIPostProcessingServiceTests.swift
    ├── WhisperServiceTests.swift
    ├── NotionServiceTests.swift
    └── HotkeyServiceTests.swift
```

## Tech Stack

| Component | Technology |
|---|---|
| UI | SwiftUI (MenuBarExtra) |
| Audio Capture | AVFoundation + CoreAudio |
| Transcription | whisper.cpp / OpenAI Whisper (local) |
| AI Summaries | Ollama (local) or OpenAI API |
| Notion Sync | Notion REST API v1 + OAuth 2.0 |
| Local Storage | SQLite via GRDB.swift |
| Secrets | macOS Keychain |
| Hotkeys | Carbon HIToolbox |

## Notion Database Schema

VoiceLog creates meeting pages with:

| Property | Type | Description |
|---|---|---|
| Meeting Title | Title | Auto-suggested, user-editable |
| Date | Date | Recording start time |
| Duration (min) | Number | Recording length in minutes |
| Summary | Rich Text | AI-generated summary |
| Status | Select | Draft / Reviewed / Archived |
| Whisper Model | Select | Model size used |

**Page body** includes: Summary section, Action Items (checkboxes), Key Decisions (bullets), and Full Transcript (collapsed toggle).

## Configuration

Settings are accessible via the gear icon in the menu bar popover or `Cmd+,`:

- **General** — Launch at login, storage path, retention period
- **Audio** — Input device selection
- **Transcription** — Whisper model size, language override
- **AI** — Local (Ollama) vs cloud (OpenAI), model selection
- **Notion** — Workspace connection, database selection
- **Hotkey** — Global shortcut configuration

## Roadmap

| Version | Scope |
|---|---|
| **v1.0** | Core loop: record, transcribe, summarize, sync to Notion |
| **v1.1** | System audio capture, transcript editing, Markdown export |
| **v2.0** | Speaker diarization, calendar auto-trigger |
| **v2.5** | Team mode, Slack integration |

## License

MIT
