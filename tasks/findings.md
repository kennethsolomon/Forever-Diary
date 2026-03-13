# Offload Dictation Processing — Local Server + Engine Selector

## Problem Statement

The `whisper-large-v3-turbo` model (~809MB) causes:
1. **Excessive processing time** — batch transcription after recording stops takes too long
2. **Phone overheating** — iPhone 14 Pro Max heats up running the large model on Neural Engine
3. **Overkill for short recordings** — user's typical recordings are < 10 seconds

## Key Decisions

1. **Add Local Server engine** — OpenAI-compatible API (`POST /v1/audio/transcriptions`) pointing to user's laptop running whisper.cpp server or similar
2. **Downgrade on-device WhisperKit** from `large-v3-turbo` (~809MB) to `whisper-small` (~244MB) — lighter, less heat, adequate as backup
3. **Keep Apple Speech** as a third engine option (no Tagalog, but useful for English)
4. **Explicit engine selection via dropdown** — no automatic fallback chain; user picks which engine to use
5. **Engine picker in two places** — Settings (default) + Recording view (per-recording override)
6. **Error handling** — if selected engine fails, show error and let user pick different engine (no silent fallback)
7. **Configurable server URL** — editable in Settings, default `http://localhost:8080`

## Chosen Approach: Multi-Engine with Explicit Selection

### Engine Options

| Engine | Where it runs | Model | Tagalog? | Needs network? |
|--------|--------------|-------|----------|----------------|
| Local Server | User's laptop (whisper.cpp server) | large-v3-turbo (or any) | Yes | Yes (LAN) |
| WhisperKit | On-device (iPhone) | whisper-small (~244MB) | Yes | No |
| Apple Speech | On-device (Apple framework) | Apple's built-in | No | No |

### API Format (Local Server)

OpenAI-compatible endpoint — works with whisper.cpp server, faster-whisper-server, LocalAI, or OpenAI cloud:

```
POST {serverURL}/v1/audio/transcriptions
Content-Type: multipart/form-data

file: <audio.wav>
model: whisper-1
language: tl  (or en, ja, etc.)
```

Response: `{ "text": "transcribed text here" }`

### UI Changes

#### Settings
- **Default Engine** dropdown: Local Server / WhisperKit / Apple Speech
- **Server URL** text field (shown when Local Server selected or always visible)
- **WhisperKit Model** section updated: shows whisper-small (~244MB) instead of large-v3-turbo
- Keep existing: favorite languages, language picker

#### Recording View
- **Engine picker** (segmented control or dropdown) — defaults to Settings choice, can override per-recording
- Keep existing: language quick-switch pills, waveform, timer

### Error Handling

- Local Server unreachable → show error alert: "Server unreachable at {URL}. Switch engine or check server."
- WhisperKit model not downloaded → show error: "WhisperKit model not downloaded. Download in Settings or switch engine."
- Apple Speech fails → show error with reason
- No silent fallback — user always chooses

### Changes Required

#### 1. SpeechService.swift
- Add `TranscriptionEngine` enum: `.localServer`, `.whisperKit`, `.appleSpeech`
- Add `transcribeWithLocalServer(url:language:)` — multipart POST to configurable endpoint
- Change WhisperKit model from `openai_whisper-large-v3_turbo` to `openai_whisper-small`
- Add `serverURL` property (stored in UserDefaults)
- Add `selectedEngine` property (stored in UserDefaults)
- Modify `transcribe()` to dispatch to selected engine, no fallback chain
- Return errors explicitly instead of silently falling back

#### 2. RecordingView.swift
- Add engine picker (segmented control or menu) defaulting to Settings choice
- Show engine-specific status (e.g., "Sending to server..." vs "Processing on device...")
- Handle engine errors with alert + engine switch option

#### 3. SettingsView.swift
- Add "Default Engine" picker
- Add "Server URL" text field
- Update WhisperKit model info (~244MB whisper-small)
- Keep favorite languages section

### Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Open Questions

- None — all decisions made
