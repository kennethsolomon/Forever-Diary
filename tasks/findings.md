# Improve Dictation — Tagalog Support & Accuracy

## Problem Statement

The speech-to-text dictation feature has poor Tagalog support:
1. **No Filipino/Tagalog in the language list** — list comes from `SFSpeechRecognizer.supportedLocales()` which lacks `fil-PH` on the user's device. Only `en-PH` (English Philippines) appears, which doesn't understand Tagalog.
2. **WhisperKit auto-detect fails for Tagalog** — the `whisper-base` model defaults to English when hearing Tagalog.
3. **WhisperKit ignores language selection** — `transcribe()` is called without a `language` parameter, so the picker has no effect on WhisperKit.
4. **Noise artifacts in output** — `[cough]`, `[music]`, `[laughter]` tokens appear in transcribed text.
5. **User speaks Taglish** (mixed Tagalog + English) — needs a model that handles code-switching.

## Key Decisions

1. **Upgrade WhisperKit model** from `whisper-base` (~74MB) to `whisper-large-v3-turbo` (~809MB) — same size as medium, large-v3 quality, best accuracy-to-speed ratio for multilingual
2. **Use WhisperKit's language list** — WhisperKit supports 99 languages including Tagalog (`tl`). Show WhisperKit-supported languages instead of only Apple's `SFSpeechRecognizer.supportedLocales()`
3. **Pass language explicitly** to `whisperKit.transcribe(language:)` when a language is selected — eliminates bad auto-detection
4. **Keep "Auto-detect" option** — works better with the larger model, still available for users who want it
5. **Post-process transcription output** — strip noise tokens (`[cough]`, `[music]`, `[laughter]`, `[applause]`, etc.) from WhisperKit results
6. **Favorite languages with quick-switch** — pin user's preferred languages (e.g., English + Filipino) at the top of the picker for fast switching
7. **Apple Speech becomes fallback-only** — WhisperKit is the recommended primary for Tagalog since Apple Speech doesn't support Filipino on-device

## Chosen Approach: WhisperKit-first with large-v3-turbo

### Changes Required

#### 1. SpeechService.swift
- Change model from `openai_whisper-base` to `openai_whisper-large-v3-turbo`
- Pass `language` parameter to `whisperKit.transcribe(language:)` when not "auto"
- Map locale identifiers to Whisper language codes (e.g., `fil-PH` → `tl`, `en-US` → `en`)
- Add post-processing to strip noise tokens from transcription output
- Add WhisperKit-supported languages list (static, since Whisper's language set is fixed)
- Add favorite languages storage (UserDefaults array)

#### 2. RecordingView.swift / LanguagePickerView
- Show merged language list: WhisperKit languages + Apple Speech locales (deduplicated)
- Favorites section pinned at top of language picker
- Add/remove favorite via swipe or toggle
- Quick-switch pill on RecordingView shows favorites for one-tap switching

#### 3. SettingsView.swift
- Update model size display (~809MB instead of ~40-75MB)
- Add "Favorite Languages" management section

### WhisperKit Language Code Mapping (subset)

| Display Name | Whisper Code | Apple Locale |
|-------------|-------------|-------------|
| Filipino (Tagalog) | `tl` | not supported |
| English | `en` | `en-US`, `en-PH`, etc. |
| Japanese | `ja` | `ja-JP` |
| Korean | `ko` | `ko-KR` |
| Chinese | `zh` | `zh-CN`, `zh-TW` |

### Noise Tokens to Strip

`[cough]`, `[music]`, `[laughter]`, `[applause]`, `[silence]`, `[noise]`, `[blank_audio]`, `(cough)`, `(music)`, etc. — regex pattern: `\[[\w\s]+\]|\([\w\s]+\)`

### Affected Files

- **Modified:** `ForeverDiary/Services/SpeechService.swift` — model upgrade, language passing, post-processing, favorites
- **Modified:** `ForeverDiary/Views/Speech/RecordingView.swift` — quick-switch pill, updated language picker
- **Modified:** `ForeverDiary/Views/Settings/SettingsView.swift` — model size, favorite languages

### Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Open Questions

- None — all decisions made
