<p align="center">
  <img src="Logo/forever-diary-logo.png" alt="Forever Diary" width="500">
</p>

<h1 align="center">Forever Diary</h1>

<p align="center">A daily diary iOS app that layers your entries by date across years — so you can revisit what you wrote on this day, every year, forever. Offline-first with optional AWS cloud sync.</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue?style=flat&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-framework-0071E3?style=flat&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Backend-AWS-FF9900?style=flat&logo=amazonaws&logoColor=white" alt="AWS">
  <img src="https://img.shields.io/badge/Tests-58%20passing-brightgreen?style=flat" alt="Tests">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat" alt="License">
</p>

---

## Features

**Journaling**
- Write-first experience — open the app and start typing immediately with auto-save
- Yearless calendar — browse by month and day, not by year
- "On this day" timeline — tap any day to see entries stacked across years
- Rich text entries with location tagging via reverse geocoding

**Check-ins & Photos**
- Daily check-ins — track mood, gratitude, exercise, sleep, and weight
- Customizable fields (boolean, text, number) via configurable templates
- Attach up to 10 photos per entry with compression and thumbnails

**Speech-to-Text**
- Three transcription engines: Local Whisper Server (primary), WhisperKit on-device, Apple Speech
- Multilingual support including Tagalog/Filipino via whisper.cpp
- User selects engine explicitly — no automatic fallback

**Analytics & Sync**
- Analytics dashboard — streaks, completion rates, and habit trends via Swift Charts
- Offline-first cloud sync — SwiftData is the source of truth, AWS syncs in the background
- Anonymous authentication — no sign-up required via AWS Cognito Identity Pool

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 |
| Framework | SwiftUI (iOS 17+) |
| Database | SwiftData (offline-first) |
| Backend | AWS Lambda (Node.js), DynamoDB, S3, Cognito |
| Speech | whisper.cpp server, WhisperKit, Apple Speech |
| Charts | Swift Charts |
| Project Gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |
| Testing | XCTest (58 tests) |

## Requirements

- Xcode 16.0+
- iOS 17.0+
- Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Homebrew](https://brew.sh/) (for whisper.cpp)

## Prerequisites: Whisper Server Setup

The speech-to-text feature requires a local whisper.cpp server running on your Mac. Your iPhone and Mac must be on the same Wi-Fi network.

### 1. Install whisper.cpp

```bash
brew install whisper-cpp
```

### 2. Download a model

```bash
# large-v3-turbo (~1.5 GB) — best accuracy for multilingual/Tagalog
curl -L -o ~/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

Other model options:

| Model | Size | Best for |
|-------|------|----------|
| large-v3-turbo | ~1.5 GB | Best accuracy, multilingual |
| medium | ~1.5 GB | Good balance |
| small | ~466 MB | Faster, less accurate |
| base | ~142 MB | Fastest, least accurate |

### 3. Start the server

```bash
whisper-server -m ~/ggml-large-v3-turbo.bin --port 8080 --host 0.0.0.0
```

### 4. Find your Mac's IP

```bash
ipconfig getifaddr en0
```

### 5. Verify it works

```bash
curl -v http://localhost:8080 2>&1 | grep -i "server:"
```

> **Note:** Audio is sent over plaintext HTTP. This is fine on a trusted home/office network — avoid public Wi-Fi. See [docs/whisper-server-setup.md](docs/whisper-server-setup.md) for the full guide including auto-start on boot and troubleshooting.

## Setup

```bash
# Clone the repository
git clone https://github.com/kennethsolomon/Forever-Diary.git
cd Forever-Diary

# Generate the Xcode project (do not edit .xcodeproj directly)
brew install xcodegen   # if not installed
xcodegen generate

# Open in Xcode
open ForeverDiary.xcodeproj
```

Select an iOS 17+ simulator and press **Cmd+R**.

### Configure Speech-to-Text

1. Open **Settings** > **Speech** in the app
2. Select **Server** as the engine
3. Set **Server URL** to `http://<your-mac-ip>:8080`
4. Tap **Test** to verify connectivity

### AWS Backend (Optional)

The app works fully offline without AWS. To enable cloud sync:

1. Set up a Cognito Identity Pool (unauthenticated access)
2. Create a DynamoDB table and S3 bucket
3. Deploy the Lambda function from `aws/lambda/`
4. Update `ForeverDiary/Services/AWSConfig.swift` with your resource IDs

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   iOS App                       │
│  ┌───────────┐  ┌───────────┐  ┌────────────┐  │
│  │  SwiftUI  │  │ SwiftData │  │  Services  │  │
│  │   Views   │──│  Models   │──│ Sync/Auth  │  │
│  └───────────┘  └───────────┘  └─────┬──────┘  │
│                                      │         │
└──────────────────────────────────────┼─────────┘
                                       │
                              SigV4-signed HTTPS
                                       │
┌──────────────────────────────────────┼─────────┐
│                  AWS Cloud           │         │
│  ┌──────────┐  ┌──────────┐  ┌──────┴──────┐  │
│  │ Cognito  │  │ DynamoDB │  │ API Gateway │  │
│  │ Identity │  │  Tables  │  │  + Lambda   │  │
│  └──────────┘  └──────────┘  └─────────────┘  │
│                ┌──────────┐                    │
│                │    S3    │                    │
│                │  Photos  │                    │
│                └──────────┘                    │
└────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│              Local Network                      │
│  ┌──────────────────────────────────────┐       │
│  │  whisper.cpp server (Mac)            │       │
│  │  HTTP :8080 ← iPhone audio upload    │       │
│  └──────────────────────────────────────┘       │
└─────────────────────────────────────────────────┘
```

### Data Model

Entries use a `(monthDayKey, year)` composite key — this enables the "on this day" experience:

| Model | Purpose |
|-------|---------|
| `DiaryEntry` | Core entry with text, location, date, and relationships |
| `CheckInTemplate` | Configurable field definitions (mood, exercise, etc.) |
| `CheckInValue` | Per-entry values for each check-in field |
| `PhotoAsset` | Photo metadata with compressed image data and thumbnails |

### Sync Strategy

1. **SwiftData is always the source of truth** — the app works fully offline
2. On connectivity, `SyncService` pushes local changes to DynamoDB/S3 via Lambda
3. Anonymous Cognito credentials are stored in Keychain
4. Photos upload to S3 with presigned URLs; metadata syncs via DynamoDB
5. Batch operations capped at 100 items with exponential backoff on failures

## Project Structure

```
ForeverDiary/
├── App/
│   └── ForeverDiaryApp.swift        # Entry point, container setup, sync init
├── Models/
│   ├── DiaryEntry.swift             # @Model — core diary entry
│   ├── CheckInTemplate.swift        # @Model — check-in field definitions
│   ├── CheckInValue.swift           # @Model — per-entry check-in data
│   ├── CheckInFieldType.swift       # Enum: boolean, text, number
│   └── PhotoAsset.swift             # @Model — photo attachment metadata
├── Views/
│   ├── ContentView.swift            # Root tab navigation
│   ├── Home/HomeView.swift          # Today's entry (write-first)
│   ├── Entry/EntryDetailView.swift  # Full entry view with all fields
│   ├── Calendar/
│   │   ├── CalendarBrowserView.swift # Month carousel + day grid
│   │   └── TimelineView.swift       # Year-stacked entries for a date
│   ├── Analytics/AnalyticsView.swift # Streaks, charts, completion stats
│   ├── Settings/SettingsView.swift  # Templates, sync, speech config
│   └── Speech/
│       ├── RecordingView.swift      # Audio recording + transcription UI
│       └── WaveformView.swift       # Live audio waveform visualization
├── Services/
│   ├── SpeechService.swift          # Tri-engine speech-to-text orchestrator
│   ├── SyncService.swift            # Offline-first sync orchestrator
│   ├── APIClient.swift              # SigV4-signed API Gateway requests
│   ├── CognitoAuthService.swift     # Anonymous Cognito authentication
│   ├── AWSConfig.swift              # AWS region, endpoints, pool IDs
│   ├── KeychainHelper.swift         # Secure credential storage
│   ├── LocationService.swift        # CLLocationManager wrapper
│   └── TemplateSeedService.swift    # Default check-in template seeding
├── Assets.xcassets/                 # Colors, app icon, image assets
├── Info.plist                       # Privacy usage descriptions
└── ForeverDiary.entitlements        # App capabilities

ForeverDiaryTests/                   # 58 XCTest unit tests
aws/lambda/                          # Node.js Lambda (DynamoDB + S3 operations)
docs/whisper-server-setup.md         # Full Whisper server guide
```

## Running Tests

```bash
xcodebuild test \
  -scheme ForeverDiary \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Privacy & Permissions

| Permission | Usage |
|------------|-------|
| **Location (When In Use)** | Tag diary entries with where you were |
| **Photo Library** | Attach existing photos to entries |
| **Camera** | Take new photos to attach to entries |
| **Microphone** | Record audio for speech-to-text transcription |

No data is collected without user action. All data stays on-device unless cloud sync is explicitly enabled.

## Security

- Anonymous authentication — no email, password, or personal info required
- Credentials stored in iOS Keychain (not UserDefaults)
- All API requests signed with SigV4
- Lambda validates and sanitizes all input; strips user-controlled partition keys
- Photo uploads validated against 10MB size limit
- Whisper server identity verified before sending audio
- Audio sent over local network only — no cloud transcription

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
