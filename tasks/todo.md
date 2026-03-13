# Improve Dictation — Tagalog Support & Accuracy

## Goal

Fix Tagalog/Filipino speech-to-text by upgrading WhisperKit to `large-v3-turbo`, switching to WhisperKit's language list (99 languages including Tagalog), passing language explicitly to transcription, stripping noise tokens, and adding favorite languages with quick-switch UI.

## Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Plan

### Phase 1 — SpeechService: Language Data & Favorites

- [x] 1. Add static `whisperSupportedLanguages: [(code: String, name: String)]` array to `SpeechService.swift` — all 99 Whisper language codes with human-readable names (English, Filipino (Tagalog), Japanese, etc.)
- [x] 2. Add `displayName(for code: String) -> String` helper that looks up a Whisper code and returns the display name
- [x] 3. Change `languageIdentifier` storage from Apple locale identifiers (`en-US`) to Whisper language codes (`en`, `tl`, `auto`). Default to `"auto"` instead of `Locale.current.identifier`
- [x] 4. Add `favoriteLanguages: [String]` property backed by UserDefaults — array of Whisper language codes. Default to `["en", "tl"]`
- [x] 5. Add `addFavorite(_:)` / `removeFavorite(_:)` methods with a cap of 5 favorites
- [x] 6. Update `currentLocaleDisplayName` to use the new Whisper language list instead of `Locale.localizedString`

### Phase 2 — SpeechService: Model Upgrade & Language Passing

- [x] 7. Change model identifier from `"openai_whisper-base"` to `"openai_whisper-large-v3_turbo"` in both `transcribeWithWhisperKit()` and `downloadWhisperModel()`
- [x] 8. Pass `language` parameter to `whisperKit.transcribe(audioPath:, decodeOptions:)` via `DecodingOptions(language:)` — use stored language code when not `"auto"`, omit when `"auto"`
- [x] 9. Add `cleanTranscription(_: String) -> String` method — strips noise tokens matching `\[[\w\s]+\]` and `\([\w\s]+\)` patterns, trims extra whitespace
- [x] 10. Apply `cleanTranscription()` to WhisperKit results in `transcribeWithWhisperKit()`

### Phase 3 — SpeechService: Apple Speech Locale Mapping

- [x] 11. Add `whisperCodeToAppleLocale(_: String) -> String?` mapping for Apple Speech fallback
- [x] 12. Update `startAudioEngine()` to use mapped Apple locale — if mapping returns nil, skip Apple Speech live streaming (record-only mode)
- [x] 13. Update `transcribeFileWithAppleSpeech()` to use mapped locale

### Phase 4 — RecordingView: Quick-Switch Pills

- [x] 14. Add quick-switch favorite pills to RecordingView top bar
- [x] 15. Update `languagePill` to show display name from the new Whisper language list

### Phase 5 — LanguagePickerView: Redesign

- [x] 16. Rewrite `LanguagePickerView` to use `SpeechService.whisperSupportedLanguages`
- [x] 17. Add `.searchable` modifier for filtering languages by name
- [x] 18. Add "Favorites" section at top with star icon, "Auto-detect" always available
- [x] 19. Add swipe actions — swipe right to add to favorites, swipe left to remove
- [x] 20. Show "Not supported by Apple Speech" caption below unsupported languages

### Phase 6 — macOS Settings Update

- [x] 21. Update `SpeechTab` in `SettingsMacView.swift` — change language picker data source to `whisperSupportedLanguages`
- [x] 22. Show model name `large-v3-turbo` and size `~809 MB` in WhisperKit model status row (both iOS and macOS)

### Phase 7 — Cleanup & Build

- [x] 23. Remove `static var supportedLocales` from SpeechService (replaced by `whisperSupportedLanguages`)
- [x] 24. Run `xcodegen generate` and build iOS — BUILD SUCCEEDED
- [x] 25. Build macOS — BUILD SUCCEEDED (fixed `.navigationBarDrawer` iOS-only API)
- [x] 26. Run existing tests — 152/152 pass

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'
```

## Acceptance Criteria

1. Filipino (Tagalog) appears in language list and is selectable
2. Selecting Tagalog and speaking Tagalog produces accurate Tagalog transcription (via WhisperKit large-v3-turbo)
3. Auto-detect with larger model correctly identifies Tagalog speech
4. No `[cough]`, `[music]`, or other noise tokens in transcription output
5. Favorite languages appear as quick-switch pills on RecordingView
6. Language picker has search, favorites section, and swipe-to-favorite
7. Apple Speech fallback works for supported languages, gracefully skipped for unsupported ones (like Tagalog)
8. Both iOS and macOS build successfully, all existing tests pass
