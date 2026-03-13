# Speech-to-Text Subsystem (March 13, 2026)

## Summary

Added tri-engine speech-to-text subsystem (Local Server via whisper.cpp, WhisperKit on-device, Apple Speech) with shared service, platform-specific UI, and new SPM dependency.

## Type of Architectural Change

**New Subsystem + Configuration + Integration**

## What Changed

**New Service:**
- `ForeverDiary/Services/SpeechService.swift` — `@Observable` service with tri-engine transcription (Local Server, WhisperKit, Apple Speech), audio recording, server connection testing, and model management

**New Views:**
- `ForeverDiary/Views/Speech/RecordingView.swift` — Recording sheet (iOS) / popover (macOS) with waveform, timer, live transcript
- `ForeverDiary/Views/Speech/WaveformView.swift` — Animated 5-bar audio level visualization

**Configuration Changes:**
- `project.yml` — Added WhisperKit SPM package (`argmaxinc/WhisperKit` from 0.9.0), added dependency to both iOS/macOS targets, added Speech directory as shared macOS source, added microphone entitlement and permission keys

**Modified Views (integration points):**
- `HomeView.swift`, `EntryDetailView.swift` — Mic button + recording sheet
- `EntryEditorView.swift` (macOS) — Mic button + recording popover
- `SettingsView.swift`, `SettingsMacView.swift` — Engine picker, language selection, WhisperKit model management

**Statistics:**
- Lines added: 1604
- Lines removed: 153
- Files modified: 20

## Impact

- New `SpeechService` injected via SwiftUI `.environment()` from app entry points
- WhisperKit adds ~50MB model download (on-demand, not bundled)
- New OS permissions: microphone access + speech recognition authorization
- Conditional compilation: `#if canImport(WhisperKit)` gates WhisperKit code paths

## Detailed Changes

Added a new speech-to-text subsystem that provides voice dictation for diary entries. The architecture uses a tri-engine approach: (1) Local Server — sends recorded audio to a whisper.cpp server on the local network via HTTP POST to `/inference`, validated by Server header; (2) WhisperKit — on-device Whisper inference using whisper-small model; (3) Apple Speech — SFSpeechRecognizer streams live transcription during recording. All engines write to a shared .wav temp file. User explicitly selects engine — no automatic fallback chain. `NSAllowsLocalNetworking` ATS exception enables plaintext HTTP to local server.

## Before & After

**Before:**
Text entry only — users type diary entries manually via keyboard.

**After:**
Users can tap a mic button to dictate entries. Audio is captured via AVAudioEngine with a tap that simultaneously writes to a temp .wav file, feeds Apple Speech for live preview, and computes audio levels for waveform visualization. On stop, the selected engine transcribes and the result is appended to the entry text.

## Affected Components

- App entry points (ForeverDiaryApp, ForeverDiaryMacApp) — new service initialization + environment injection
- Home and Entry Detail views — new mic button in action bars
- Settings views — new speech configuration section
- project.yml — new SPM dependency and build configuration
- Info.plist / entitlements — new permission declarations

## Migration/Compatibility

Backward compatibility confirmed. No breaking changes — speech is additive. Existing entries and sync are unaffected. WhisperKit model download is opt-in via Settings.

## Verification

- [x] All affected code paths tested (75 unit tests for SpeechService, 197 total)
- [x] Related documentation updated (CHANGELOG.md)
- [x] No breaking changes (or breaking changes documented)
- [x] Dependent systems verified (iOS + macOS builds pass)
