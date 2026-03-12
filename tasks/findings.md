# Speech-to-Text for Diary Entries

## Problem Statement

Users want to dictate diary entries by speaking into the mic instead of typing. The app needs accurate transcription supporting English, Tagalog (Filipino), and other languages. Both iOS and macOS platforms must be supported.

## Key Decisions

1. **Dual-engine architecture** — Apple Speech (SFSpeechRecognizer) + WhisperKit, user picks primary in Settings, the other is automatic fallback
2. **Fallback trigger** — If primary engine returns error or empty result, automatically retry with fallback (transparent to user)
3. **Append mode** — Transcribed text appends to existing diary text (not replace)
4. **Interaction** — Tap mic to start → waveform + live text preview → tap to stop → final text appended
5. **Language** — Default to device locale; inline language picker remembers last choice. Apple Speech uses explicit locale (`fil-PH`, `en-US`, etc.). WhisperKit auto-detects language.
6. **5-minute cap** per recording session. User can pause and record again to append more.
7. **WhisperKit model download** — Proactive: download when user selects WhisperKit in Settings, not on first use
8. **Same UI** regardless of active engine — mic button + waveform visualization
9. **All text editors** — HomeView, EntryDetailView, and any other editable text fields on both platforms
10. **macOS too** — Shared SpeechService in `ForeverDiary/Services/`, platform-specific UI

## Chosen Approach: Hybrid (Apple Speech Primary + WhisperKit Fallback)

### Architecture

- **`SpeechService.swift`** (shared, in `ForeverDiary/Services/`) — Protocol-based orchestrator
  - `SpeechEngineProtocol` — Common interface for both engines
  - `AppleSpeechEngine` — Uses `SFSpeechRecognizer` + `AVAudioEngine` for live streaming
  - `WhisperKitEngine` — Uses WhisperKit for record-then-transcribe
  - `SpeechService` — Orchestrator that calls primary, falls back to secondary on failure
- **Settings toggle** — "Speech Engine" picker: Apple Speech (default) | WhisperKit
  - Selecting WhisperKit triggers model download immediately
  - Display model download progress + size
- **UI components** (platform-specific):
  - Mic button in action bar (iOS) / toolbar (macOS)
  - Waveform visualization overlay/sheet during recording
  - Live text preview while recording (Apple Speech only; WhisperKit shows after stop)

### Engine Behavior

| Feature | Apple Speech | WhisperKit |
|---------|-------------|------------|
| Live text preview | Yes (streaming) | No (after stop) |
| Language detection | Explicit locale required | Automatic |
| Offline | Yes (iOS 17+ on-device) | Yes (on-device model) |
| Time limit | ~1 min server, longer on-device | 5 min cap (our limit) |
| Model download | None | ~40-75MB on first selection |
| Fallback role | Secondary when WhisperKit is primary | Secondary when Apple Speech is primary |

### Permissions Needed

- `NSSpeechRecognitionUsageDescription` — iOS Info.plist + project.yml
- `NSMicrophoneUsageDescription` — iOS Info.plist + project.yml
- `com.apple.security.device.audio-input` — macOS entitlements

### Affected Files

- **New:** `ForeverDiary/Services/SpeechService.swift` — Dual-engine orchestrator
- **Modified:** `ForeverDiary/Views/Home/HomeView.swift` — Mic button + waveform (iOS)
- **Modified:** `ForeverDiary/Views/Entry/EntryDetailView.swift` — Mic button + waveform (iOS)
- **Modified:** `ForeverDiaryMac/Views/Editor/EntryEditorView.swift` — Mic button + waveform (macOS)
- **Modified:** `ForeverDiary/Views/Settings/SettingsView.swift` — Engine picker + model download
- **Modified:** `ForeverDiaryMac/Views/Settings/SettingsMacView.swift` — Engine picker + model download
- **Modified:** `ForeverDiary/Info.plist` — Mic + speech permissions
- **Modified:** `project.yml` — Permissions + WhisperKit SPM dependency
- **Modified:** `ForeverDiaryMac/ForeverDiaryMac.entitlements` — Audio input entitlement

### Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check
- No new security patterns flagged — mic/speech are standard iOS permissions

## Open Questions

- None — all decisions made
