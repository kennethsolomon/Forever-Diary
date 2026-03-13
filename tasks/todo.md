# Offload Dictation Processing — Local Server + Engine Selector

## Goal

Replace the heavy on-device `large-v3-turbo` model with a multi-engine architecture: configurable local Whisper server (primary), on-device `whisper-small` (fallback), and Apple Speech (option). User explicitly selects engine via dropdown in Settings and Recording view. No automatic fallback — errors shown, user decides.

## Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Plan

### Phase 1: SpeechEngineType enum update
- [x] 1. Add `.localServer` case to `SpeechEngineType` with `rawValue: "localserver"`, `displayName: "Local Server"`. Add `shortName` computed property (`"Server"`, `"Whisper"`, `"Apple"`). Add `symbolName` computed property (`"antenna.radiowaves.left.and.right"`, `"cpu"`, `"mic"`).

### Phase 2: SpeechService — server URL + connection test
- [x] 2. Add `serverURL` property to `SpeechService` — UserDefaults-backed (`"whisperServerURL"`), default `"http://localhost:8080"`.
- [x] 3. Add `serverConnectionState` enum (`untested`, `testing`, `connected`, `failed(String)`) and observable property.
- [x] 4. Add `testServerConnection()` method — `GET {serverURL}/v1/models` with 5-second timeout, updates `serverConnectionState`.

### Phase 3: SpeechService — local server transcription
- [x] 5. Add `transcribeWithLocalServer(url: URL) async -> String` — multipart POST to `{serverURL}/v1/audio/transcriptions` with `file` (WAV data), `model: "whisper-1"`, `language` param. Parse JSON response `{ "text": "..." }`. On error, set `self.error` with descriptive message (server unreachable, timeout, bad response).
- [x] 6. Apply `cleanTranscription()` to local server results (same noise token stripping).

### Phase 4: SpeechService — engine dispatch refactor
- [x] 7. Change WhisperKit model from `"openai_whisper-large-v3_turbo"` to `"openai_whisper-small"` in both `transcribeWithWhisperKit()` and `downloadWhisperModel()`.
- [x] 8. Update `whisperModelRow` display text from `"large-v3-turbo (~809 MB)"` to `"small (~244 MB)"` in SettingsView and SettingsMacView.
- [x] 9. Refactor `stopRecording()` — replace fallback logic with single-engine dispatch. Added `stopRecording(using:)` with optional engine override + `retryTranscription(using:)` + `finishSession()` for cleanup.

### Phase 5: Settings UI — iOS
- [x] 10. Update `speechSection` in SettingsView — segmented picker now has 3 options using `shortName`.
- [x] 11. Add server URL `TextField` row — shown when engine is `.localServer`.
- [x] 12. Add connection test row below URL — status dot + text + "Test" button.
- [x] 13. Update footer text.

### Phase 6: Settings UI — macOS
- [x] 14. Update `SpeechTab` in SettingsMacView — segmented picker with 3 options.
- [x] 15. Add server URL field + connection test to macOS SpeechTab, centered layout.
- [x] 16. Update model display text to `"small (~244 MB)"`.
- [x] 17. Update footer text to match iOS.

### Phase 7: Recording View — engine picker
- [x] 18. Add `@State private var activeEngine: SpeechEngineType?` with `currentEngine` computed property.
- [x] 19. Add `enginePill` view — capsule with Menu dropdown, SF Symbol + shortName + chevron.
- [x] 20. Insert `enginePill` as first element in top `HStack`.
- [x] 21. Update `statusLabel` with engine-specific processing text.
- [x] 22. Update `stopRecording()` call to use `currentEngine` for per-recording override.

### Phase 8: Recording View — error handling
- [x] 23. Retry button shown when error occurs or result empty. Calls `retryTranscription(using:)`. Engine pill tints red on error. Done button only shown when text available.

### Phase 9: Build + verify
- [x] 24. Run `xcodegen generate` — succeeded.
- [x] 25. Build iOS (iPhone 16e) — BUILD SUCCEEDED.
- [x] 26. Build macOS — BUILD SUCCEEDED.
- [x] 27. Run tests (iPhone 16e) — 179/179 pass (2 new tests for shortName/symbolName).

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'
```

## Acceptance Criteria

1. [x] `SpeechEngineType` has 3 cases: `.localServer`, `.whisperKit`, `.apple`
2. [x] Settings (iOS + macOS) shows 3-option segmented engine picker
3. [x] Settings shows server URL text field + connection test when Local Server selected
4. [x] WhisperKit model is `whisper-small` (~244MB), not `large-v3-turbo`
5. [x] Recording view has engine pill with Menu dropdown to override engine per-recording
6. [x] Selecting Local Server sends multipart POST to `{serverURL}/v1/audio/transcriptions`
7. [x] No automatic fallback — engine failure shows error, user picks alternative
8. [x] Status label reflects active engine ("Sending to server..." / "Processing on device..." / "Listening...")
9. [x] All existing tests pass, both iOS and macOS build
