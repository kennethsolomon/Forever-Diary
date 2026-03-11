# Security Findings

> Populated by `/security-check`. Never overwritten — new audits append below.
> Referenced by `/review`, `/finish-feature`, and `/brainstorm` for security context.

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
