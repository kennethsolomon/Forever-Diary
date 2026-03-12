# Speech-to-Text Dictation

## Goal

Add voice dictation to all diary text editors (iOS + macOS) with dual-engine support: Apple Speech (SFSpeechRecognizer) as default, WhisperKit as fallback. User picks primary engine in Settings; the other auto-fallbacks on failure.

## Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Plan

### Phase 1 — Config & Permissions

- [x] 1. Add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` to `ForeverDiary/Info.plist`
- [x] 2. Add matching `INFOPLIST_KEY_` entries to `project.yml` for the iOS target
- [x] 3. Add `com.apple.security.device.audio-input` to `ForeverDiaryMac/ForeverDiaryMac.entitlements` and `project.yml` entitlements
- [x] 4. Add WhisperKit SPM package to `project.yml` (both iOS and macOS targets as dependency)

### Phase 2 — SpeechService (shared, in `ForeverDiary/Services/`)

- [x] 5. Create `SpeechService.swift` with:
  - `SpeechEngineProtocol` — common interface: `startRecording(locale:)`, `stopRecording() async -> String`, `audioLevel` (Float, for waveform), `transcribedText` (live partial), `isRecording`, `error`
  - `AppleSpeechEngine` — `SFSpeechRecognizer` + `AVAudioEngine` live streaming; updates `transcribedText` with partial results; supports explicit locale; requests on-device recognition when available
  - `WhisperKitEngine` — records to temp file via `AVAudioRecorder`; on stop, transcribes with WhisperKit; manages model download (download, progress, delete); auto language detection
  - `SpeechService` (`@Observable`) — orchestrator: picks primary/fallback based on `@AppStorage("speechEngine")` (default: "apple"); on `startRecording()` → start primary engine; on `stopRecording()` → if primary returns error/empty, auto-retry with fallback; 5-min timer auto-stops; permission requests (`SFSpeechRecognizer.requestAuthorization` + `AVAudioSession.requestRecordPermission` on iOS, just mic on macOS)
  - `@AppStorage("speechLanguage")` for language (default: device locale)
  - `whisperModelState` enum: `.notDownloaded`, `.downloading(progress: Double)`, `.downloaded`, `.error(String)`
  - `downloadWhisperModel()`, `deleteWhisperModel()` methods

### Phase 3 — Shared UI Components

- [x] 6. Create `ForeverDiary/Views/Speech/WaveformView.swift`:
  - 5 vertical `RoundedRectangle` bars, 4pt wide, 4pt spacing
  - Height driven by `audioLevel` array (8pt silent → 40pt loud)
  - `accentBright` fill, `.spring(response: 0.15, dampingFraction: 0.6)` animation
  - Idle state: all bars at 8pt, opacity pulses 0.3↔0.6 with `.easeInOut(duration: 1.0).repeatForever()`
- [x] 7. Create `ForeverDiary/Views/Speech/RecordingView.swift`:
  - Language pill (shows current locale name, tappable → language picker sheet/popover)
  - Time remaining label (mm:ss countdown from 5:00, turns `destructive` color at 0:30)
  - WaveformView (centered)
  - Live transcript ScrollView (.body/.serif, auto-scrolls to bottom, max ~120pt height)
  - Status label: "Listening..." when Apple Speech active, "Recording..." when WhisperKit active, "Processing..." after stop while WhisperKit transcribes
  - Stop button: Capsule, `destructive` fill, white `square.fill` icon + "Stop" label, 44pt height, 140pt width
  - Language picker: list of supported locales, checkmark for current, "Auto-detect" option when WhisperKit is primary
- [x] 8. Add `ForeverDiary/Views/Speech` as a shared source path in `project.yml` macOS target sources

### Phase 4 — iOS Integration

- [x] 9. `HomeView.swift`: Add mic button to action bar (between location button and Spacer):
  - `Label("Dictate", systemImage: "mic")` / `"mic.fill"` when recording
  - `.caption` / `.rounded` / `textSecondary` (idle) or `accentBright` (recording)
  - `.symbolEffect(.variableColor.iterative)` when recording
  - `@State private var showRecording = false`
  - `.sheet(isPresented: $showRecording)` with `.presentationDetents([.medium])` containing RecordingView
  - On completion: append `" " + transcribedText` to `diaryText`, call `debounceSave(text: diaryText)`
- [x] 10. `EntryDetailView.swift`: Add mic button as a small inline button next to diary section heading or as a toolbar trailing item; same sheet + append pattern

### Phase 5 — macOS Integration

- [x] 11. `EntryEditorView.swift` (macOS): Add mic button to action bar (HStack, before photo count label):
  - Same styling as iOS
  - `.popover(isPresented: $showRecording)` containing RecordingView
  - Min width 320pt for popover
  - Same text append pattern on completion

### Phase 6 — Settings

- [x] 12. `SettingsView.swift` (iOS): Add "Speech" section after Appearance:
  - Segmented picker: "Apple Speech" | "WhisperKit" → `@AppStorage("speechEngine")`
  - Navigation row for language: shows current locale display name, taps to language list
  - WhisperKit model status row (visible when WhisperKit selected or model already downloaded):
    - `.notDownloaded`: "Download Model" button with model size info
    - `.downloading`: ProgressView with percentage
    - `.downloaded`: checkmark + "Delete Model" destructive button
    - `.error`: error text + "Retry" button
  - Section footer: "The other engine is used as fallback if the primary fails."
- [x] 13. `SettingsMacView.swift` (macOS): Add "Speech" tab (Label("Speech", systemImage: "mic.circle")):
  - Same controls as iOS adapted to macOS tab layout pattern
  - Centered icon + heading + segmented picker + language picker + model status

### Phase 7 — App Entry Points

- [x] 14. Inject `SpeechService` via `.environment()` in:
  - `ForeverDiaryApp.swift`: create instance alongside other services, pass to ContentView
  - `ForeverDiaryMacApp.swift`: same, pass to both WindowGroup and Settings scenes
  - Guard with `isTestHost` check (lazy init or skip entirely during tests)

### Phase 8 — Verify

- [x] 15. Run `xcodegen generate` and build iOS: `xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e' build` — BUILD SUCCEEDED
- [x] 16. Build macOS: `xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build` — BUILD SUCCEEDED
- [x] 17. Run existing tests: `xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'` — 122/122 pass

## Verification Commands

```bash
# Regenerate Xcode project
xcodegen generate

# Build iOS
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build macOS
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build

# Run tests
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all builds succeed, all existing tests pass.

## Acceptance Criteria

1. Mic button visible in HomeView action bar, EntryDetailView, and macOS EntryEditorView action bar
2. Tapping mic opens recording sheet (iOS `.medium` detent) or popover (macOS, 320pt min width) with waveform + live text
3. Tapping stop appends transcribed text to diary entry and triggers existing debounce save
4. Settings shows engine picker (Apple Speech / WhisperKit), language picker, model download status
5. Fallback engine auto-used when primary returns error or empty result (transparent to user)
6. 5-minute recording cap with visual countdown (last 30s in destructive color)
7. Mic + speech recognition permissions requested on first use with descriptive messages
8. WhisperKit model downloads proactively when selected in Settings with progress indicator
9. All existing tests pass; both iOS and macOS build successfully

## Risks / Unknowns

- **WhisperKit + XcodeGen SPM syntax**: XcodeGen uses `packages:` top-level key + target `dependencies` with `package:` reference. May need iteration to get the exact YAML syntax right.
- **Simulator limitations**: SFSpeechRecognizer may not produce output on simulator without real microphone. Manual device testing needed for full validation.
- **Filipino locale**: `fil-PH` is in Apple's supported locales for iOS 17+, but on-device model quality unknown until device testing.
- **WhisperKit model size**: ~40-75MB download. Need graceful error handling for network failures during download.
- **Audio session**: AVAudioEngine/AVAudioRecorder setup must not conflict with system audio. App currently has no audio, so this should be clean.
- **macOS speech permissions**: macOS handles microphone permission via system dialog on first AVAudioEngine use. No `NSMicrophoneUsageDescription` needed in Info.plist for macOS, but the entitlement `com.apple.security.device.audio-input` is required for sandboxed apps.
