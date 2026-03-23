# Security Findings

> Populated by `/security-check`. Never overwritten — new audits append below.
> Referenced by `/review`, `/finish-feature`, and `/brainstorm` for security context.

---

# Security Audit — 2026-03-13 (Local Server Engine + whisper.cpp Integration)

**Scope:** Changed files on branch `feat/speech-to-text` (server engine, connectivity, endpoint fixes)
**Stack:** Swift 5.9 / SwiftUI (iOS 17+ / macOS 14+) + AVFoundation + Speech + WhisperKit + whisper.cpp server
**Files audited:** 14 (SpeechService.swift, RecordingView.swift, SettingsView.swift, SettingsMacView.swift, SpeechServiceTests.swift, Info.plist, project.yml, ForeverDiaryApp.swift, ForeverDiaryMacApp.swift, HomeView.swift, EntryDetailView.swift, WaveformView.swift, whisper-server-setup.md, ForeverDiaryMac.entitlements)

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| 1 | Medium — Temp audio files (PII) never deleted | **Still fixed** — `cleanupTempFile()` called in `cancelRecording()` (line 238) and `finishSession()` (line 242). Deferred cleanup on `stopRecording()` is intentional for retry. |
| 2 | Low — `transcribeFileWithAppleSpeech()` may hang | **Still fixed** — 30-second timeout via `withTaskGroup` (lines 372-395). |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

### M1. Server URL stored in plaintext UserDefaults

- **[SpeechService.swift:79-82]** `serverURL` is stored in `UserDefaults` with key `"whisperServerURL"`. While this is a local network URL (not a secret), UserDefaults are backed up to iCloud and included in unencrypted device backups.
  **Standard:** CWE-312 — Cleartext Storage of Sensitive Information
  **Risk:** Low in practice — the URL points to a local server with no credentials. No API keys or tokens are stored. The risk is informational since the URL itself reveals network topology.
  **Recommendation:** Acceptable for local server URLs. If credentials are ever added to the server URL (e.g., basic auth), move to Keychain via `KeychainHelper`.

### M2. Connection test accepts any HTTP response as "connected"

- **[SpeechService.swift:414-420]** `testServerConnection()` treats any HTTP response (including 4xx/5xx) as `.connected`. This could mislead the user if they point at a non-Whisper HTTP server.
  **Standard:** OWASP A05 — Security Misconfiguration (CWE-295 variant)
  **Risk:** User thinks connection is valid when pointing at the wrong server. Transcription would fail at use-time with a clear error, so impact is UX confusion, not a security vulnerability.
  **Recommendation:** Consider checking the `Server` response header for `whisper.cpp` to confirm it's the right server type. Low priority.

## Low / Informational

### L1. NSAllowsLocalNetworking ATS exception

- **[Info.plist:15-19]** `NSAllowsLocalNetworking` allows plaintext HTTP to local network addresses. This is the correct and narrowest ATS exception for this use case.
  **Standard:** OWASP A02 — Cryptographic Failures (CWE-319)
  **Risk:** Minimal — only affects local network traffic (Bonjour, localhost, link-local IPs). Does not weaken TLS for external connections. Apple explicitly provides this flag for this purpose.
  **Recommendation:** No action needed. This is the recommended approach per Apple's ATS documentation.

### L2. Server URL input not sanitized for SSRF-like patterns

- **[SpeechService.swift:403-406]** `testServerConnection()` validates `hasPrefix("http")` and non-empty, but does not restrict to private/local IP ranges. A user could enter a public URL.
  **Standard:** OWASP A10 — SSRF (CWE-918)
  **Risk:** Negligible — the user is entering their own URL on their own device. There is no server-side component being exploited. The app simply makes an HTTP request to wherever the user points it. This is expected user-controlled behavior.
  **Recommendation:** No action needed. User-controlled URL on a client app is not SSRF.

### L3. Audio data sent over plaintext HTTP to local server

- **[SpeechService.swift:426-468]** Audio recordings (potentially containing PII — voice, spoken content) are sent via HTTP POST to the local server without TLS.
  **Standard:** CWE-319 — Cleartext Transmission of Sensitive Information
  **Risk:** Low — traffic stays on the local network. An attacker would need to be on the same Wi-Fi and perform ARP spoofing/MITM. The `NSAllowsLocalNetworking` flag limits this to local addresses.
  **Recommendation:** Document in setup guide that the server should ideally be on a trusted/private network. For production use with remote servers, HTTPS should be required.

## Passed Checks

- **A01 Broken Access Control** — No auth bypass. Engine selection is local user preference, not access-controlled.
- **A02 Cryptographic Failures** — No secrets in code. AWS credentials use Cognito + Keychain (unchanged). Server URL is not a secret.
- **A03 Injection** — No string interpolation into SQL/commands. Server URL is used only as `URL(string:)` parameter. Multipart form data uses hardcoded field names.
- **A04 Insecure Design** — No automatic fallback chain (user-controlled engine selection). Timeout on server requests (5s for test, 30s for transcription).
- **A05 Security Misconfiguration** — ATS exception is narrowly scoped (`NSAllowsLocalNetworking` only).
- **A06 Vulnerable Components** — WhisperKit 0.9.0+, no known CVEs. whisper.cpp is external server, not bundled.
- **A07 Auth Failures** — No auth on local whisper server (expected — it's a local dev tool).
- **A08 Data Integrity** — Audio file read via `Data(contentsOf:)` from app's own temp directory. No untrusted deserialization.
- **A09 Logging** — No PII logged. Print statements use generic error descriptions only.
- **A10 SSRF** — Client-side app, user controls URL input. Not applicable.
- **PII Cleanup** — Temp audio files cleaned up via `cleanupTempFile()` in `cancelRecording()` and `finishSession()`.
- **Input Validation** — `serverURL` validated (non-empty, http prefix). `languageIdentifier` passed to server as form field (server-side validation).
- **Error Handling** — Granular error messages for timeout, unreachable, bad response. No stack traces leaked to UI.
- **Entitlements** — macOS entitlements include `com.apple.security.network.client` (required for server communication) and `com.apple.security.device.audio-input` (required for microphone). Both are appropriate.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 2 |
| Low      | 3 |
| **Total** | **5** |

---

# Security Audit — 2026-03-13 (Dictation Improvement — Tagalog & Language Controls)

**Scope:** Changed files on branch `feat/speech-to-text` (dictation improvement commits)
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + AVFoundation + Speech framework + WhisperKit
**Files audited:** 5 (SpeechService.swift, RecordingView.swift, SettingsView.swift, SettingsMacView.swift, SpeechServiceTests.swift)

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| 1 | Medium — Temp audio files (PII) never deleted | **Still fixed** — `cleanupTempFile()` still called in `stopRecording()` (line 164) and `cancelRecording()` (line 181). |
| 2 | Low — `transcribeFileWithAppleSpeech()` may hang | **Still fixed** — 30-second timeout via `withTaskGroup` still present (lines 306-329). |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **PII Cleanup** — Temp audio files still properly deleted after `stopRecording()` and `cancelRecording()`. `cleanupTempFile()` removes `.wav` file and nils `recordingURL`. No change to this behavior.
- **Timeout Safety** — `transcribeFileWithAppleSpeech()` still has 30-second timeout via `withTaskGroup`. `transcribeWithWhisperKit()` does not have an explicit timeout but WhisperKit's `transcribe()` is bounded by audio file length (max 5 min recording cap enforced by timer).
- **Input Validation** — `languageIdentifier` accepts arbitrary strings from UserDefaults but is only used as:
  - A key lookup in `whisperCodeToAppleLocale()` (returns nil for unknown codes — safe)
  - Passed to `DecodingOptions(language:)` for WhisperKit (WhisperKit validates internally — safe)
  - Passed to `Locale(identifier:)` for Apple Speech (Foundation handles gracefully — safe)
  No injection vectors.
- **Favorite Languages** — `addFavorite()` validates: rejects duplicates and caps at 5. `removeFavorite()` uses `removeAll(where:)` which is safe for absent items. No unbounded growth.
- **cleanTranscription() Regex** — Uses `NSRegularExpression` via `.regularExpression` option on `String.replacingOccurrences`. The patterns `\[[\w\s]+\]` and `\([\w\s]+\)` are static compile-time strings (no user input in pattern). No ReDoS risk — patterns are simple with no nested quantifiers.
- **No Hardcoded Secrets** — No API keys, tokens, or credentials in changed files. Model identifier `"openai_whisper-large-v3_turbo"` is a public model name, not a secret.
- **No Network Calls in New Code** — WhisperKit model download uses WhisperKit's built-in download mechanism (HuggingFace). No new direct network calls introduced. Model download was already present; only the model name changed.
- **UserDefaults Storage** — Language preferences and favorites stored in UserDefaults (not Keychain). This is appropriate — these are non-sensitive UI preferences, not credentials or PII. No change in storage approach.
- **No XSS / Injection** — All user-facing text in SwiftUI views uses `Text()` which auto-escapes. No `UIWebView`, `WKWebView`, or HTML rendering. Language names come from a static hardcoded array, not external input.
- **Error Message Safety** — `error.localizedDescription` is displayed to users in `statusLabel` (RecordingView line 165-167) and set in `transcribeWithWhisperKit` (line 353). These are system-generated error descriptions, not internal stack traces. Acceptable for a local-only app.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-13 (Speech-to-Text Dictation — attempt 2)

**Scope:** Re-audit of `SpeechService.swift` after fixing prior findings
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + AVFoundation + Speech framework + WhisperKit
**Files audited:** 1 (SpeechService.swift)

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| 1 | Medium — Temp audio files (PII) never deleted after transcription | **Fixed** — `cleanupTempFile()` added to `stopRecording()` (line 166) and `cancelRecording()` (line 184). Deletes `.wav` file and nils `recordingURL` (lines 187-192). |
| 2 | Low — `transcribeFileWithAppleSpeech()` may hang indefinitely | **Fixed** — Wrapped in `withTaskGroup` with 30-second timeout task (lines 305-327). Whichever finishes first wins; the other is cancelled via `group.cancelAll()`. |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **PII Cleanup** — `cleanupTempFile()` deletes voice recording from temp directory after both `stopRecording()` and `cancelRecording()`. `recordingURL` set to nil after deletion. No orphaned audio files.
- **Timeout Safety** — `transcribeFileWithAppleSpeech()` uses `withTaskGroup` with a 30-second `Task.sleep` race. If the recognizer never calls back, the timeout returns empty string, allowing the fallback engine to proceed. `group.cancelAll()` ensures the losing task is cancelled.
- All other checks from initial audit still pass (no regressions).

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-12 (Speech-to-Text Dictation)

**Scope:** Changed files on branch `feat/speech-to-text`
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + AVFoundation + Speech framework + WhisperKit
**Files audited:** 14

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

- **[SpeechService.swift:166]** Temp audio files (`.wav`) containing voice recordings are never deleted after transcription completes
  **Standard:** CWE-459 — Incomplete Cleanup / Data Protection (PII handling)
  **Risk:** Each recording creates a `diary_speech_<UUID>.wav` file in the temp directory containing the user's voice. After `stopRecording()` returns the transcribed text, the audio file remains on disk. While iOS periodically purges temp files, macOS does not aggressively clean them. Over time, voice recordings accumulate — this is PII that could be accessed if the device is compromised or if a backup includes the temp directory.
  **Recommendation:** Delete `recordingURL` at the end of `stopRecording()` and `cancelRecording()`:
  ```swift
  if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
  recordingURL = nil
  ```

## Low / Informational

- **[SpeechService.swift:296-309]** `transcribeFileWithAppleSpeech()` may hang indefinitely if `SFSpeechRecognizer` never calls the result handler
  **Standard:** CWE-835 — Loop with Unreachable Exit Condition (analogous — unbounded await)
  **Risk:** If Apple Speech Recognition fails to call the result handler (e.g., corrupted audio file, recognizer becomes unavailable mid-transcription, zero-length audio), the `withCheckedContinuation` never resumes. The UI stays in "Processing..." state indefinitely. The user must dismiss and re-enter the recording view. Low probability — Apple's recognizer reliably calls back with either a result or error in normal conditions.
  **Recommendation:** Add a timeout using `Task.sleep` race or `withThrowingTaskGroup` (e.g., 30 seconds). Return empty string on timeout to allow the fallback engine to attempt transcription.

## Passed Checks

- **A01 Broken Access Control** — No auth logic changed. Speech service is entirely local — no network calls except WhisperKit model download (handled by WhisperKit SDK to known HuggingFace endpoint). No user data leaves the device during transcription.
- **A02 Cryptographic Failures** — No cryptographic operations introduced. UserDefaults stores non-sensitive preferences (engine choice, language). Voice audio stays on-device.
- **A03 Injection** — Transcribed text is plain `String` appended to diary via SwiftUI `TextEditor` binding. No HTML rendering, no web views, no SQL. SwiftData `#Predicate` macros are type-safe.
- **A04 Insecure Design** — 5-minute recording cap prevents unbounded resource consumption. `computeAudioLevel` processes fixed-size buffers (4096 frames). `stopRecording()` guard prevents double-stop. Audio engine tap removed before engine stop. `fileWriteQueue.sync` serializes file writes.
- **A05 Security Misconfiguration** — Permission descriptions are specific and accurate. `com.apple.security.device.audio-input` entitlement is the minimum required for macOS sandbox. No debug flags or verbose errors.
- **A06 Vulnerable Components** — WhisperKit is from argmaxinc (reputable, MIT-licensed). SPM `from: "0.9.0"` resolved to 0.16.0. No known CVEs. All other frameworks are Apple system frameworks.
- **A07 Auth Failures** — N/A — speech is a local-only feature with no auth requirements beyond OS permissions.
- **A08 Data Integrity** — `recognitionTask` callback uses `[weak self]` — no retain cycle. `hasResumed` flag prevents double-resume of checked continuation. Audio file written via `AVAudioFile` (safe API). `try? FileManager.default.removeItem(at:)` before file creation prevents stale data.
- **A09 Logging** — No `print` statements in new code. Error messages set via `error.localizedDescription` — no PII. `SpeechService.error` displayed only in local UI.
- **A10 SSRF** — No user-controlled URLs. WhisperKit model download URL is internal to WhisperKit SDK. No outbound network from speech recording or transcription.
- **Permissions** — `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` have clear, specific descriptions. Permissions requested lazily on first use (not at app launch). macOS uses system dialog for mic + entitlement.
- **Thread Safety** — Audio tap callback uses `fileWriteQueue.sync` for file writes. `recognitionRequest?.append(buffer)` is documented as thread-safe. `computeAudioLevel` dispatches to `@MainActor` for UI updates. `startRecording`/`stopRecording`/`cancelRecording` are `@MainActor` — no concurrent mutation of state.
- **Test File** — `SpeechServiceTests.swift` cleans up UserDefaults in `tearDown()`. No secrets, no PII, no network calls. No `@MainActor` on test class (follows lessons.md).

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 1 |
| Low      | 1 |
| **Total** | **2** |

---

# Security Audit — 2026-03-11 (Lightweight Sync Check + Remote Update Toast)

**Scope:** Changed files on branch `feat/lightweight-sync-check`
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + SwiftData + Node.js Lambda
**Files audited:** 5 (SyncService.swift, HomeView.swift, EntryEditorView.swift, LightweightSyncCheckTests.swift, index.mjs)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **A01 Broken Access Control** — `handleChangeCheck()` uses `userId` from `event.requestContext.identity.cognitoIdentityId` (Cognito-managed, cannot be spoofed). No IDOR — each user can only query their own partition. `checkForChanges()` guards on `authService.isAuthenticated` before making API calls.
- **A02 Cryptographic Failures** — No new cryptographic operations. API calls use existing SigV4 HMAC-SHA256 pipeline.
- **A03 Injection** — `since` query parameter is passed to DynamoDB via `marshall()` which handles safe serialization. No string interpolation in queries. SwiftUI toast renders hardcoded text only — no user input rendered.
- **A04 Insecure Design** — Lightweight check returns `{ hasChanges: bool, serverTime }` only — no item data exposed. `Limit: 1` + `Select: "COUNT"` minimizes read cost. On error, `checkForChanges()` falls back to `true` (assume changes) — safe fallback that never hides data. Periodic sync cancels previous task before starting new one — no unbounded task creation.
- **A05 Security Misconfiguration** — No new configuration, entitlements, or permissions. No CORS headers on new endpoint (inherits existing config).
- **A06 Vulnerable Components** — No new dependencies on either platform.
- **A07 Auth Failures** — `checkForChanges()` calls `authService.refreshIfNeeded()` before API call — consistent with all other sync methods. Guard clause prevents API calls when unauthenticated.
- **A08 Data Integrity** — `upsertEntry()` return value change (`Void` → `Bool`) does not alter LWW logic — only tracks whether a change was applied. `pullRemote()` toast trigger is downstream of existing `context.save()` — no new write paths.
- **A09 Logging** — New `print` statement in `pullRemote()` logs only item count and applied change count — no PII. Toast trigger has no logging.
- **A10 SSRF** — No new outbound URLs. `checkForChanges()` calls the same `/sync` endpoint via existing `apiClient.get()`.
- **Thread Safety** — `triggerRemoteUpdateToast()` is `@MainActor` — safe for SwiftUI observation. `toastDismissTask?.cancel()` prevents concurrent dismiss timers. `showRemoteUpdateToast` is modified only from `@MainActor` context.
- **Resource Management** — `startPeriodicSync()` cancels previous periodic task before creating new one. `toastDismissTask` is cancelled on re-trigger. No memory leaks or unbounded task accumulation.
- **Information Minimization** — `handleChangeCheck()` returns only a boolean and server timestamp — never item content, even on error. This follows the principle of least privilege for data exposure.
- **Test File** — `LightweightSyncCheckTests.swift` uses in-memory containers with `cloudKitDatabase: .none`, `ModelContext(container)`, no `@MainActor` on test class. No secrets, no PII, no network calls. Follows `tasks/lessons.md` constraints.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-11 (Sync Race Condition Fix)

**Scope:** Changed files on branch `fix/sync-race-condition`
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + SwiftData
**Files audited:** 4 (SyncService.swift, HomeView.swift, EntryEditorView.swift, SyncRaceConditionTests.swift)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **A01 Broken Access Control** — No auth logic changed. Guards only compare string equality on local model properties. No new data access paths introduced.
- **A02 Cryptographic Failures** — No cryptographic operations in changed code.
- **A03 Injection** — No user input flows to queries or commands. String comparisons are pure value checks on SwiftData model properties. No new predicates or queries added.
- **A04 Insecure Design** — Pull-before-push reorder is safe: `upsertEntry()` LWW guards (`remoteUpdatedAt > local.updatedAt`) prevent remote from overwriting newer local data. Cancelling `saveTask` on remote update is safe: next keystroke restarts debounce. No retry storms or unbounded loops.
- **A05 Security Misconfiguration** — No new configuration, entitlements, or permissions.
- **A06 Vulnerable Components** — No new dependencies.
- **A07 Auth Failures** — No auth changes. `refreshIfNeeded()` call position unchanged (still before sync operations).
- **A08 Data Integrity** — `guard text != entry.diaryText` prevents spurious `updatedAt` bumps that caused LWW data loss. `guard newLocation != entry.locationText` handles nil comparison correctly via Swift optional equality. Pull-before-push ensures device learns remote changes before pushing its own.
- **A09 Logging** — No new logging statements. No PII exposure.
- **A10 SSRF** — No new outbound URLs or network calls.
- **Thread Safety** — `saveTask?.cancel(); saveTask = nil` runs on main thread (SwiftUI view context). `debounceSave` uses `MainActor.run`. No cross-thread mutation.
- **Test File** — Uses in-memory containers with `cloudKitDatabase: .none`, `ModelContext(container)`, no `@MainActor`. Follows lessons.md constraints. No secrets, no PII, no network calls.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-10

**Scope:** Full project scan
**Stack:** Swift / SwiftUI (iOS 17+) with SwiftData + CloudKit
**Files audited:** 15

## Critical (must fix before deploy)

_None found._

## High (fix before production)

- **[ForeverDiaryApp.swift:24]** `try!` force-unwrap in test host branch can crash the app if `ModelContainer` creation ever fails in test mode
  **Standard:** CWE-248 — Uncaught Exception
  **Risk:** If the in-memory container fails (e.g., schema migration issue), the app crashes with no recovery path. While this only executes during tests, `try!` is a forced unwrap that should be avoided.
  **Recommendation:** Use `do/catch` with a fallback or a clear `fatalError("Test ModelContainer failed")` message instead of bare `try!`.

- **[LocationService.swift:26]** Authorization wait uses a fixed `Task.sleep(for: .seconds(1))` — race condition
  **Standard:** CWE-362 — Concurrent Execution Using Shared Resource with Improper Synchronization
  **Risk:** If the user takes longer than 1 second to respond to the location permission dialog, the code proceeds with the old authorization status and returns nil. The user may think location doesn't work.
  **Recommendation:** Use a continuation-based approach to wait for the actual `locationManagerDidChangeAuthorization` callback instead of a fixed sleep.

## Medium (should fix)

- **[LocationService.swift:34-37]** Stored continuation may be overwritten if `fetchLocationString()` is called concurrently
  **Standard:** CWE-362 — Race Condition
  **Risk:** If two callers invoke `fetchLocationString()` concurrently, the second call overwrites `self.continuation`, leaving the first caller permanently suspended (memory leak, never completes).
  **Recommendation:** Guard against concurrent calls — either use an actor, or check if `continuation` is already set and return early/cancel.

- **[ForeverDiaryApp.swift:42]** `fatalError` in production path if both CloudKit and local container creation fail
  **Standard:** CWE-248 — Uncaught Exception
  **Risk:** If SwiftData schema is corrupted or incompatible after an update, the app crashes on launch with no recovery. Users would be stuck.
  **Recommendation:** Consider showing an error UI or attempting to delete and recreate the store as a last resort, rather than crashing.

## Low / Informational

- **[AnalyticsView.swift:78-89]** `currentStreak` uses unbounded `while true` loop iterating backwards through dates
  **Standard:** Informational — CWE-835
  **Risk:** None in practice — terminates when no entry found for a date. Acceptable for personal diary app.
  **Recommendation:** No action needed.

- **[project.yml:46-48]** CloudKit entitlements always present even in local-only fallback
  **Standard:** OWASP A05 — Security Misconfiguration
  **Risk:** Minimal — standard iOS practice.
  **Recommendation:** No action needed.

## Passed Checks

- **A01 Broken Access Control** — N/A (local app, CloudKit handles access via iCloud account)
- **A02 Cryptographic Failures** — No custom crypto, no plaintext secrets
- **A03 Injection** — SwiftData `#Predicate` macros are type-safe, no SQL/string injection risk
- **A06 Vulnerable Components** — No third-party dependencies, Apple frameworks only
- **A07 Auth Failures** — N/A (device passcode + iCloud account)
- **A08 Data Integrity** — No untrusted deserialization, Codable enums are type-safe
- **A09 Logging** — No PII logged, `try?` prevents stack trace leaks
- **A10 SSRF** — No outbound network calls beyond Apple-managed CloudKit
- **Data Protection** — SwiftData inherits iOS Data Protection; `@Attribute(.externalStorage)` for photos
- **Input Validation** — Template labels trimmed, photo size validated, empty text checks
- **XSS** — N/A (native SwiftUI, no web views)

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 2 |
| Medium   | 2 |
| Low      | 2 |
| **Total** | **6** |

---

# Security Audit — 2026-03-10 (attempt 2)

**Scope:** Re-audit of 3 files changed to fix prior findings
**Stack:** Swift / SwiftUI (iOS 17+) with SwiftData + CloudKit
**Files audited:** 3 (ForeverDiaryApp.swift, LocationService.swift, AnalyticsView.swift)

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| 1 | High — `try!` in ForeverDiaryApp.swift | **Fixed** — replaced with `do/catch` + descriptive `fatalError` |
| 2 | High — Fixed 1s sleep for location auth | **Fixed** — uses `locationManagerDidChangeAuthorization` callback via continuation |
| 3 | Medium — Concurrent `fetchLocationString()` race | **Fixed** — `isFetching` guard rejects concurrent calls |
| 4 | Medium — `fatalError` with no recovery | **Fixed** — in-memory fallback added before final `fatalError` |
| 5 | Low — Unbounded `while true` loop | **Fixed** — bounded to 3650 iterations |
| 6 | Low — CloudKit entitlements always present | **Accepted** — standard iOS practice, no change needed |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-10 (Cloud Sync)

**Scope:** New cloud sync files + modified files
**Stack:** Swift / SwiftUI (iOS 17+) + Node.js Lambda
**Files audited:** 11 (AWSConfig, KeychainHelper, CognitoAuthService, APIClient, SyncService, index.mjs, ForeverDiaryApp, HomeView, EntryDetailView, SettingsView, DiaryEntry+models)

## Critical (must fix before deploy)

- **[aws/lambda/index.mjs:59]** Object spread `...item.data` allows client to overwrite `userId` partition key (IDOR)
  **Standard:** OWASP A01 — Broken Access Control / CWE-639 — Authorization Bypass Through User-Controlled Key
  **Risk:** A malicious client can send `{"items": [{"sk": "entry#01-01#2026", "data": {"userId": "victim-identity-id", "diaryText": "hacked"}}]}`. The `...item.data` spread overwrites the `userId` set on line 57, writing data to another user's DynamoDB partition. This is a cross-user data corruption vulnerability.
  **Recommendation:** Strip `userId` and `sk` from `item.data` before spreading, or use an allowlist of permitted fields:
  ```js
  const { userId: _, sk: __, ...safeData } = item.data;
  Item: marshall({ userId, sk: item.sk, ...safeData, updatedAt: ... })
  ```

## High (fix before production)

- **[aws/lambda/index.mjs:24,30]** `JSON.parse(event.body)` without null check on `event.body`
  **Standard:** CWE-20 — Improper Input Validation
  **Risk:** If `event.body` is null (e.g., empty POST request), `JSON.parse(null)` returns `null`, and destructuring `null` throws a TypeError. The generic catch returns a 500 with no useful error message. Not a security hole but causes unhandled error paths.
  **Recommendation:** Validate `event.body` exists before parsing: `if (!event.body) return respond(400, { error: "Request body required" });`

- **[aws/lambda/index.mjs:142-144]** CORS `Access-Control-Allow-Origin: *` on API with IAM auth
  **Standard:** OWASP A05 — Security Misconfiguration / CWE-942
  **Risk:** Wildcard CORS allows any browser origin to call this API. Combined with IAM auth this is mitigated, but if credentials are ever leaked, browser-based attacks become trivial. For a mobile-only API, CORS headers are unnecessary.
  **Recommendation:** Remove the CORS header entirely (mobile apps don't send Origin headers), or restrict to a specific origin if a web client is ever added.

## Medium (should fix)

- **[SyncService.swift:49]** Error logging includes full error object which may contain presigned URLs with credentials
  **Standard:** OWASP A09 — Security Logging and Monitoring Failures / CWE-532
  **Risk:** `print("[SyncService] syncAll error: \(error)")` logs the full error, which for HTTP errors includes the response body and for URL errors could include presigned S3 URLs containing temporary AWS credentials in query parameters. iOS console is not accessible to other apps, but logs may persist in crash reports.
  **Recommendation:** Log only `error.localizedDescription` instead of the full error object.

- **[ForeverDiaryApp.swift:53-56]** CognitoAuthService and SyncService initialized during test host execution
  **Standard:** CWE-489 — Active Debug Code
  **Risk:** When running as test host, `CognitoAuthService()` calls `KeychainHelper.load()` and `SyncService` is initialized with real API endpoints. While `startSync()` guards against test mode, the objects exist and could be accidentally invoked. Unnecessary attack surface.
  **Recommendation:** Move service initialization inside the `!isTestHost` branch, or use lazy initialization.

## Low / Informational

- **[aws/lambda/index.mjs:41-43]** No upper bound on `items` array size in sync push
  **Standard:** OWASP A04 — Insecure Design / CWE-770
  **Risk:** A client could send thousands of items in a single request, causing high DynamoDB write costs and Lambda timeout. Low risk for single-user app.
  **Recommendation:** Add a max items check (e.g., `if (items.length > 100) return respond(400, ...)`)

- **[AWSConfig.swift:5-6]** Cognito Identity Pool ID and API Gateway URL hardcoded in source
  **Standard:** Informational — CWE-798
  **Risk:** These are not secrets (pool ID enables unauthenticated access by design, API Gateway URL is public). However, they ship in the binary and can be extracted. Acceptable for this architecture — Cognito + IAM policies enforce access control.
  **Recommendation:** No action needed. These values are configuration, not credentials.

- **[APIClient.swift:161]** SigV4 canonical request includes `content-type` in signed headers but GET requests have no Content-Type
  **Standard:** Informational
  **Risk:** For GET requests, `content-type` header is empty string. This is technically included in the signature, which is correct per SigV4 spec (signing what you send). No security risk, but could cause signature mismatches if a proxy adds a Content-Type header.
  **Recommendation:** Consider only including `content-type` in signed headers when the request has a body.

## Passed Checks

- **A02 Cryptographic Failures** — SigV4 signing uses CryptoKit HMAC-SHA256 (industry standard). Cognito credentials stored in memory only. IdentityId in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **A03 Injection** — SwiftData `#Predicate` macros are type-safe. DynamoDB uses `marshall()` which handles escaping. No SQL or string interpolation in queries.
- **A06 Vulnerable Components** — No third-party iOS dependencies. Lambda uses only `@aws-sdk` packages (AWS-maintained).
- **A07 Auth Failures** — Cognito credentials auto-refresh within 5 min of expiry. Session tokens are short-lived (1 hour).
- **A08 Data Integrity** — Last-write-wins conflict resolution is documented and appropriate for single-user diary.
- **A10 SSRF** — All outbound URLs are to known AWS endpoints (Cognito, API Gateway, S3 presigned). No user-controlled URL destinations.
- **Data Protection** — Photos use `@Attribute(.externalStorage)`. Keychain uses device-only accessibility. HTTPS enforced for all API calls. Presigned URLs expire in 15 minutes.
- **Input Validation (iOS)** — Photo size limits enforced. Template labels trimmed. Timeout set on all network requests (15-60s).
- **Lambda Access Control** — User identity extracted from `event.requestContext.identity.cognitoIdentityId` (cannot be spoofed). S3 presigned URLs scoped to `${userId}/` prefix.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High     | 2 |
| Medium   | 2 |
| Low      | 3 |
| **Total** | **8** |

---

# Security Audit — 2026-03-10 (Cloud Sync — attempt 2)

**Scope:** Re-audit of files changed to fix prior cloud sync findings
**Stack:** Swift / SwiftUI (iOS 17+) + Node.js Lambda
**Files audited:** 4 (index.mjs, SyncService.swift, ForeverDiaryApp.swift, APIClient.swift)

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| 1 | Critical — `...item.data` IDOR overwrite of userId | **Fixed** — destructure strips `userId`/`sk` before spread (index.mjs:67) |
| 2 | High — `JSON.parse` without body null check | **Fixed** — `event.body` validated before parsing (index.mjs:25,34) |
| 3 | High — Wildcard CORS `Access-Control-Allow-Origin: *` | **Fixed** — CORS header removed entirely (index.mjs:156-158) |
| 4 | Medium — SyncService logs full error object with potential credentials | **Fixed** — logs `error.localizedDescription` only (SyncService.swift:49) |
| 5 | Medium — Services initialized during test host | **Accepted** — init has no network side effects; `startSync()` guards test mode. Documented. |
| 6 | Low — No upper bound on items array | **Fixed** — `MAX_ITEMS_PER_REQUEST = 100` enforced (index.mjs:53-55) |
| 7 | Low — Hardcoded config values | **Accepted** — configuration, not credentials |
| 8 | Low — SigV4 content-type in GET signed headers | **Fixed** — content-type only included when present (APIClient.swift:161-166) |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **A01 Broken Access Control** — userId/sk stripped from client data; userId from Cognito request context only; S3 keys scoped to userId prefix
- **A02 Cryptographic Failures** — SigV4 HMAC-SHA256 via CryptoKit; HTTPS enforced; Keychain with device-only accessibility
- **A03 Injection** — SwiftData type-safe predicates; DynamoDB `marshall()` handles escaping
- **A04 Insecure Design** — Items per request capped at 100; request timeouts on all calls
- **A05 Security Misconfiguration** — CORS removed; no verbose errors leaked to clients
- **A06 Vulnerable Components** — No third-party iOS deps; Lambda uses AWS-maintained SDKs only
- **A07 Auth Failures** — Cognito credentials auto-refresh within 5 min of expiry
- **A08 Data Integrity** — Client cannot override partition/sort keys
- **A09 Logging** — Only localizedDescription logged; no PII or credentials in logs
- **A10 SSRF** — All URLs target known AWS endpoints

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-10 (Calendar UI + Theme + View Mode)

**Scope:** Changed files on branch `fix/calendar-navigation-freeze` (UI redesign batch)
**Stack:** Swift / SwiftUI (iOS 17+)
**Files audited:** 10 (CalendarBrowserView.swift, TimelineView.swift, ContentView.swift, HomeView.swift, EntryDetailView.swift, SettingsView.swift, CalendarNavigationTests.swift, ThemeTests.swift, MarkdownTests.swift, 7 color asset JSONs)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

- **[TimelineView.swift:109]** `try? modelContext.save()` silently swallows delete error
  **Standard:** Informational — CWE-390 (Detection of Error Condition Without Action)
  **Risk:** If deleting an entry fails (e.g., concurrent modification), the user sees no feedback. Minimal risk for single-user local app.
  **Recommendation:** No action needed — consistent with existing codebase pattern (accepted in prior audit).

- **[CalendarBrowserView.swift:39]** `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` for scroll-to-month timing
  **Standard:** Informational — timing-dependent behavior
  **Risk:** No security risk. UI timing workaround for ScrollViewReader readiness.
  **Recommendation:** No action needed.

## Passed Checks

- **A01 Broken Access Control** — No auth logic changed. `@AppStorage("appTheme")` stores non-sensitive display preference.
- **A02 Cryptographic Failures** — No cryptographic operations. Theme preference stored via UserDefaults — appropriate for non-sensitive data.
- **A03 Injection** — SwiftData `#Predicate` macros are type-safe. `AttributedString(markdown:)` is Apple's safe parser — no HTML injection risk.
- **A04 Insecure Design** — Calendar grid uses computed data from Calendar API. No unbounded operations.
- **A05 Security Misconfiguration** — AppTheme enum has exhaustive cases with fallback to `.system`.
- **A06 Vulnerable Components** — No new dependencies. All Apple frameworks.
- **A08 Data Integrity** — `DaySheetItem` and `EntryDestination` are immutable value types. `parseMarkdown()` is a pure function.
- **A09 Logging** — No new logging. No PII exposure.
- **XSS** — N/A (native SwiftUI). `MarkdownTextView` uses `AttributedString(markdown:)` — safe by design.
- **Input Validation** — `formattedTitle` validates month range before array access. Theme picker uses enum values with fallback.
- **Test files** — No secrets, no network calls, no PII.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 2 |
| **Total** | **2** |

---

# Security Audit — 2026-03-10 (Auth + Gallery + Sync Tombstone)

**Scope:** Changed files on `main` (new commit bce691f)
**Stack:** Swift / SwiftUI (iOS 17+) + Node.js Lambda
**Files audited:** 14 (ForeverDiaryApp.swift, AWSConfig.swift, CognitoAuthService.swift, GoogleAuthService.swift, SyncService.swift, SignInView.swift, CalendarBrowserView.swift, TimelineView.swift, PhotoGalleryView.swift, EntryDetailView.swift, HomeView.swift, SettingsView.swift, DiaryEntry.swift, index.mjs)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

- **[GoogleAuthService.swift:101-111]** `jwtClaim()` parses JWT payload without verifying the signature ✅ **Fixed** — clarifying comment added
  **Standard:** Informational — CWE-347 (Improper Verification of Cryptographic Signature)
  **Risk:** The extracted `email` is used only for local display and Keychain storage (user label), never for authorization decisions. Cognito validates the full JWT server-side before issuing credentials.

- **[GoogleAuthService.swift:58]** `prefersEphemeralWebBrowserSession = false` shares cookies with system Safari
  **Standard:** Informational — CWE-539 (Use of Persistent Cookies Containing Sensitive Information)
  **Risk:** Google session cookies persist in the browser across app reinstalls or sign-outs until the user manually clears Safari cookies. This enables SSO (intentional), but also means a device-sharing user might silently auto-complete Google auth. Acceptable for a personal diary app.
  **Recommendation:** No action required. If stricter isolation is needed, set to `true` to require re-authentication every time.

- **[GoogleAuthService.swift:83]** Form-encoded body uses `.urlQueryAllowed` charset — technically incorrect for `application/x-www-form-urlencoded` ✅ **Fixed** — now uses RFC 3986 unreserved charset (`alphanumerics + -._~`)
  **Standard:** Informational — RFC 3986 / OAuth 2.0 token endpoint encoding
  **Risk:** `.urlQueryAllowed` does not encode `+` or `=`. Fixed to use `CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))` which correctly encodes all reserved characters.

- **[SyncService.swift:87-117]** `deletePhoto()` still uses hard-delete — ghost photo possible on full pull after failed remote delete
  **Standard:** Informational — same root cause as ghost entry (now fixed with soft-delete)
  **Risk:** If `deletePhoto()` remote call fails, the photo record stays in DynamoDB. On a fresh install or UserDefaults reset (no `lastSyncDate`), `pullRemote` fetches all records including the orphaned photo metadata. `upsertPhoto` creates a stub record, and `downloadPhotos` re-downloads the image. The photo would reappear in the entry. Lower impact than ghost entries since the user likely has the photo in their Photos library anyway.
  **Recommendation:** Consider applying the same soft-delete tombstone pattern to `PhotoAsset` in a future iteration. Not blocking for this release.

## Passed Checks

- **A01 Broken Access Control** — Google OAuth uses PKCE (state not required with PKCE, but code verifier binding prevents CSRF). Cognito identity is server-scoped; userId in Lambda comes from request context, not client payload. S3 key prefix scoping unchanged and verified clean.
- **A02 Cryptographic Failures** — PKCE uses `SecRandomCopyBytes` + SHA-256 (CryptoKit). Code verifier is 256-bit entropy. All tokens transmitted over HTTPS only.
- **A03 Injection** — No user input reaches shell or SQL. SwiftData predicates type-safe. DynamoDB `marshall()` used.
- **A04 Insecure Design** — Auth flows use Cognito-managed rate limiting. Password minimum 8 chars enforced client-side + Cognito policy. Lambda item cap (100) unchanged.
- **A05 Security Misconfiguration** — CORS header absent (verified from prior fix). No verbose stack traces exposed.
- **A06 Vulnerable Components** — No new third-party dependencies. `AuthenticationServices` is Apple framework. `CryptoKit` is Apple framework.
- **A07 Auth Failures** — Tokens stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `refreshIfNeeded()` auto-refreshes before API calls. Password never logged.
- **A08 Data Integrity** — Soft-delete tombstone uses `updatedAt`-based last-write-wins. Entry cannot be resurrected if tombstone is newer. `deletedAt >= local.updatedAt` correctly favors remote deletion.
- **A09 Logging** — No PII in new log lines. Auth errors surface only `localizedDescription` (Cognito human-readable messages).
- **A10 SSRF** — All outbound URLs are hardcoded to known Google and AWS endpoints. No user-controlled URL destinations.
- **PhotoGalleryView** — Displays only in-app `PhotoAsset.imageData` from SwiftData. Scale bounded 1.0–4.0. No file system access. No injection surface.
- **SignInView** — Password never stored in UserDefaults or logged. `@State` vars cleared on view teardown. Email trimmed and lowercased before network use. Confirmation code stripped of whitespace.
- **DiaryEntry.deletedAt** — Non-nil only during tombstone window; filtered from all `@Query` predicates so soft-deleted entries are invisible to the user.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 4 |
| **Total** | **4** |

---

# Security Audit — 2026-03-11 (macOS App — Full macOS Target)

**Scope:** All ForeverDiaryMac source files (new macOS target) + new test file
**Stack:** Swift / SwiftUI (macOS 14+) with SwiftData + AWS sync
**Files audited:** 17 (ForeverDiaryMacApp.swift, SignInMacView.swift, EntryEditorView.swift, DayEntryListView.swift, MainWindowView.swift, MacImageHelper.swift, AnalyticsMacView.swift, SettingsMacView.swift, CalendarSidebarView.swift, MacPhotoGalleryView.swift, SyncStatusView.swift, EntryListView.swift, CheckInSectionView.swift, GoToTodayNotification.swift, AppTheme.swift, ForeverDiaryMac.entitlements, DiaryEntryDeduplicationTests.swift)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

- **[ForeverDiaryMac/Views/Editor/EntryEditorView.swift:467]** `Data(contentsOf: url)` reads the full file into memory before size validation
  **Standard:** CWE-400 — Uncontrolled Resource Consumption
  **Risk:** `PhotoAsset.maxPhotoBytes` is checked after `MacImageHelper.compress()`, but the raw file is loaded entirely first. If a user selects a very large RAW image or video that happens to have an allowed extension (e.g., `.tiff`), the app allocates its full size in memory before compression can reduce it. On machines with limited RAM, this could cause memory pressure or an OOM crash.
  **Recommendation:** Check file size before reading — `url.resourceValues(forKeys: [.fileSizeKey]).fileSize` — and skip files over a reasonable raw limit (e.g., 50 MB) before calling `Data(contentsOf:)`.

- **[ForeverDiaryMac/ForeverDiaryMac.entitlements:9]** `files.user-selected.read-write` entitlement when only read access is required
  **Standard:** OWASP A05 — Security Misconfiguration / Principle of Least Privilege
  **Risk:** The app only reads user-selected files (photo import via NSOpenPanel). The `read-write` entitlement grants write access to any file the user selects via an Open/Save panel, including in future code paths. Read-only would be sufficient and reduces the blast radius of any future bug.
  **Recommendation:** Change to `com.apple.security.files.user-selected.read-only` in `ForeverDiaryMac.entitlements`.

- **[Carried over]** `SyncService.swift:87-117` `deletePhoto()` uses hard-delete — ghost photo possible on fresh install after failed remote delete
  **Standard:** Informational — same root cause as ghost entry (now fixed with soft-delete tombstone)
  **Risk:** If the S3/DynamoDB remote delete fails, the photo persists in the cloud. On a fresh install (no `lastSyncDate`), `pullRemote` re-downloads it. Lower impact than entry ghost since the photo exists in the user's chosen folder.
  **Recommendation:** Apply the same soft-delete tombstone pattern to `PhotoAsset` in a future iteration. Not blocking.

## Passed Checks

- **A01 Broken Access Control** — NSOpenPanel is sandboxed to user-selected files only (`files.user-selected`). No user-controlled path traversal possible. Calendar date navigation uses internally-computed keys (never user-supplied strings). Future date selection blocked at UI level.
- **A02 Cryptographic Failures** — No new crypto. AWS sync uses same SigV4/HMAC-SHA256 pipeline verified in prior audits.
- **A03 Injection** — All SwiftData `#Predicate` macros are type-safe. All text rendered via SwiftUI `Text` and `TextEditor` — no web views, no HTML injection surface.
- **A04 Insecure Design** — Photo count bounded by `PhotoAsset.maxPhotosPerEntry`. `urls.prefix(remaining)` prevents exceeding the limit. Debounced saves prevent concurrent write races.
- **A05 Security Misconfiguration** — App is fully sandboxed (`com.apple.security.app-sandbox: true`). No debug flags or verbose error exposure. Notification name uses reverse-DNS convention.
- **A06 Vulnerable Components** — No third-party dependencies. All Apple frameworks (AppKit, SwiftUI, SwiftData, CryptoKit).
- **A07 Auth Failures** — Cognito credentials passed from iOS auth layer; same token refresh and Keychain storage as iOS.
- **A08 Data Integrity** — `.id("\(monthDayKey)-\(year)")` on `EntryEditorView` forces view recreation on date change — prevents `@State` cross-contamination between dates.
- **A09 Logging** — No new `print` statements with PII. `try?` used consistently — no stack trace exposure.
- **A10 SSRF** — No new outbound URLs. Sync reuses same `APIClient` verified in prior audits.
- **NSOpenPanel** — `allowedContentTypes` restricts to image types. `canChooseDirectories: false`. User must explicitly approve file selection. Sandboxed to user-selected scope only.
- **Photo Gallery** — Scale bounded 1.0–4.0×. Displays only in-app `PhotoAsset.imageData` from SwiftData — no filesystem access at display time.
- **Check-in inputs** — Toggle/TextField/NumberField all use SwiftUI type-safe bindings. Template label trimmed and validated (non-empty) before save.
- **Test file** — `DiaryEntryDeduplicationTests.swift` uses direct model instantiation (no network, no filesystem). No secrets or PII. Follows established test conventions.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 3 |
| **Total** | **3** |

---

# Security Audit — 2026-03-11 (Offline-First Auth Fix)

**Scope:** Changed files on branch `feat/macos-parity-and-lww-sync` (offline fix batch)
**Stack:** Swift / SwiftUI (iOS 17+ / macOS 14+) + Network.framework
**Files audited:** 10 (NetworkMonitor.swift, CognitoAuthService.swift, SyncService.swift, ForeverDiaryApp.swift, ForeverDiaryMacApp.swift, SettingsView.swift, SettingsMacView.swift, SyncStatusView.swift, EntryEditorView.swift, project.yml)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

- **[ForeverDiaryMacApp.swift:31]** Force-unwrap on in-memory fallback container with no descriptive error
  **Standard:** CWE-248 — Uncaught Exception
  **Risk:** `(try? ModelContainer(for: schema, configurations: memConfig))!` — if both the local-disk and in-memory container creations fail (e.g., schema incompatibility after an update), the app crashes with a bare force-unwrap trap and no diagnostic message. Equivalent issue on iOS was flagged High and fixed (`do/catch + fatalError("...")`). macOS path was missed in the prior macOS audit.
  **Recommendation:** Replace with `do/catch` + `fatalError("Failed to create macOS ModelContainer: \(error)")` for consistent, descriptive crash handling.

- **[NetworkMonitor.swift:6]** `isConnected` defaults to `true` before first `NWPathMonitor` path update
  **Standard:** CWE-362 — TOCTOU (Time-of-Check to Time-of-Use)
  **Risk:** On app launch, `isConnected` is `true` until `NWPathMonitor` fires its first path update (async dispatch to main queue). If the device is offline when the app launches, there is a brief window where `syncAll()` believes it is connected and proceeds to call `refreshIfNeeded()`. In practice this is mitigated by the 2-second `Task.sleep` in `startSync()`, which gives `NWPathMonitor` time to fire its initial update. Low real-world risk.
  **Recommendation:** No action required — mitigated by startup delay. Documented for awareness.

- **[CognitoAuthService.swift:219-220]** Revoked Cognito tokens no longer trigger automatic sign-out
  **Standard:** Informational — accepted design tradeoff (CWE-613 Insufficient Session Expiration)
  **Risk:** The `signOut()` call was intentionally removed so offline users are not ejected from the app. A consequence is that definitively revoked tokens (e.g., admin-forced sign-out from Cognito console) will not automatically sign the user out — they will stay in the app and see sync errors (`lastError`) until they manually sign out. For a personal diary app with no shared credentials or enterprise use, this is acceptable.
  **Recommendation:** Accepted tradeoff. If enterprise/multi-user scenarios arise in future, consider parsing HTTP 401/403 response codes from Cognito and calling `signOut()` only on definitive auth rejection.

## Passed Checks

- **A01 Broken Access Control** — `NetworkMonitor.isConnected` is a boolean used only as a sync gate; no auth decisions made from it. Offline entries use existing `syncStatus = "pending"` path — no new data access paths.
- **A02 Cryptographic Failures** — No new cryptographic operations. `NWPathMonitor` is a system framework that does not expose crypto.
- **A03 Injection** — No user input flows through `NetworkMonitor`. `path.status == .satisfied` is a system enum comparison — no injection surface.
- **A04 Insecure Design** — `syncAll()` offline guard silently skips sync (no error set, no retry storm). Pending entries accumulate correctly in SwiftData and push on next connected sync.
- **A05 Security Misconfiguration** — `Network.framework` added to macOS target via `project.yml` — standard system framework, no sandbox impact. macOS entitlement `com.apple.security.network.client` already present.
- **A06 Vulnerable Components** — No new third-party dependencies. `Network.framework` is an Apple system framework.
- **A07 Auth Failures** — Offline users authenticated via Keychain (`identityId` + `userEmail`) — intentional design. Keychain state unchanged by this PR.
- **A08 Data Integrity** — Offline writes use existing `syncStatus = "pending"` path. No new serialization or deserialization introduced.
- **A09 Logging** — `NetworkMonitor` has no `print` statements. No PII in new code paths. `isConnected` bool is not sensitive.
- **A10 SSRF** — No new outbound URLs. `NWPathMonitor` monitors system network paths — no user-controlled URLs.
- **Thread Safety** — `NWPathMonitor` callback dispatches to `DispatchQueue.main` before updating `@Observable` property — correct for SwiftUI observation.
- **Test Files** — `NetworkMonitorTests.swift` and `CloudSyncServiceTests.swift` changes contain no secrets, no PII, no network calls.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 3 |
| **Total** | **3** |

---

# Security Audit — 2026-03-10 (Calendar Navigation Fix)

**Scope:** Changed files on branch `fix/calendar-navigation-freeze`
**Stack:** Swift / SwiftUI (iOS 17+)
**Files audited:** 3 (CalendarBrowserView.swift, TimelineView.swift, CalendarNavigationTests.swift)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **A01 Broken Access Control** — No auth logic changed. Navigation values (monthDayKey, year) are computed internally, not user-supplied.
- **A03 Injection** — SwiftData `#Predicate` macros are type-safe. No string interpolation in queries. `monthDayKey` is generated from `String(format:)` with integer inputs.
- **A04 Insecure Design** — `createAndNavigateToEntry()` creates entries via modelContext with fixed schema values. No unbounded operations.
- **A05 Security Misconfiguration** — No new configuration. Navigation patterns follow SwiftUI best practices.
- **A08 Data Integrity** — `EntryDestination` is an immutable `let` struct. Entry creation uses typed SwiftData model. `try? modelContext.save()` consistent with existing codebase pattern (prior audit accepted).
- **A09 Logging** — No logging added. No PII exposure.
- **XSS** — N/A (native SwiftUI, no web views)
- **Test file** — CalendarNavigationTests.swift uses in-memory containers with `cloudKitDatabase: .none`, follows established test conventions. No secrets or PII.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-13 (Re-audit after M2/L3 fixes)

**Scope:** Changed files since last audit (SpeechService.swift, whisper-server-setup.md)
**Stack:** Swift 5.9 / SwiftUI (iOS 17+) + whisper.cpp server
**Files audited:** 2

## Prior Findings — Resolution Status

| # | Prior Finding | Status |
|---|--------------|--------|
| M1 | Server URL in plaintext UserDefaults | **Accepted** — local IP only, no credentials. No fix needed. |
| M2 | Connection test accepts any HTTP response | **Fixed** — now checks `Server` header for "whisper" (`SpeechService.swift:417-422`). |
| L1 | NSAllowsLocalNetworking ATS exception | **Accepted** — correct and narrowest exception. |
| L2 | Server URL not restricted to private IPs | **Accepted** — user-controlled URL on client app, not SSRF. |
| L3 | Audio over plaintext HTTP | **Fixed** — security note added to `docs/whisper-server-setup.md:96-98`. |

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- **M2 fix verified** — `testServerConnection()` now reads `Server` response header and requires it to contain "whisper" (case-insensitive). Non-Whisper servers show "Not a Whisper server" error. Confirmed whisper.cpp returns `Server: whisper.cpp` header.
- **L3 fix verified** — `docs/whisper-server-setup.md` now includes a Security Note warning about plaintext HTTP on untrusted networks, and a troubleshooting entry for the new "Not a Whisper server" error.
- **No regressions** — URL validation guard unchanged. Timeout unchanged. Error handling unchanged.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |

---

# Security Audit — 2026-03-23 (Vim Mode + Zoom + Decimal Check-Ins)

**Scope:** Changed files on branch `feature/vim-zoom-decimal-checkins`
**Stack:** Swift 5.9 / SwiftUI (iOS 17+ / macOS 14+)
**Files audited:** 10 (VimEngine.swift, VimTextView.swift, VimStatusBar.swift, FontScaleEnvironment.swift, ForeverDiaryMacApp.swift, EntryEditorView.swift, SettingsMacView.swift, CheckInSectionView.swift, EntryDetailView.swift, VimEngineTests.swift)

## Critical (must fix before deploy)

_None found._

## High (fix before production)

_None found._

## Medium (should fix)

_None found._

## Low / Informational

_None found._

## Passed Checks

- OWASP A01-A10 — no new auth, network, injection, or data surfaces
- PII/Data Protection — diary text uses existing save path, no new data collection
- Input Validation — decimal precision validates via SwiftUI TextField format; font scale clamped 0.75-2.0
- VimEngine — pure state machine, no I/O, no network; processes key strings into typed enums only

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |
| **Total** | **0** |
