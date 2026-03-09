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

