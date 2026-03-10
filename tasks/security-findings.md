# Security Findings

> Populated by `/security-check`. Never overwritten — new audits append below.
> Referenced by `/review`, `/finish-feature`, and `/brainstorm` for security context.

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
