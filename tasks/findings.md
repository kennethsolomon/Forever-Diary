# Forever Diary — Offline-First Auth Fix

## Problem Statement

When the device has no internet connection, the app redirects the user to the login screen instead of staying open. This happens on both iOS and macOS. The app should be usable offline — the user should be able to read and write diary entries with sync deferred until connectivity returns.

## Root Cause

`CognitoAuthService.refreshIfNeeded()` (line 220) unconditionally calls `signOut()` when all credential refresh network calls fail. A network timeout is not an auth failure — but the code treats them identically.

Flow:
1. App launches → Keychain has `identityId` + `userEmail` → `isAuthenticated = true`
2. `startSync()` → `syncAll()` → `refreshIfNeeded()`
3. All 4 refresh paths fail (no network) → `signOut()` → `isAuthenticated = false`
4. App shows `SignInView` — wrong

## Key Decisions

1. **Fix A: Remove `signOut()` from `refreshIfNeeded()`**
   - When all credential refresh attempts fail, return without signing out
   - `credentials` stays nil; sync calls will throw and be caught by `syncAll()`'s catch block
   - `isAuthenticated` stays true (Keychain still valid)
   - Sign-out should only happen on explicit user action or definitive HTTP 401/403 from Cognito

2. **Fix C: Add `NWPathMonitor` reachability guard**
   - Wrap `Network.framework` in a lightweight `NetworkMonitor` observable
   - In `syncAll()`, skip the entire sync when offline (no `refreshIfNeeded()` call, no network I/O)
   - Expose `isConnected: Bool` so the Settings sync status row can show an "Offline" badge
   - `NWPathMonitor` starts on app foreground, stops on background (tied to `scenePhase`)

## Chosen Approach

**A + C combined:**
- A is the defensive root fix (correct behavior even without C)
- C adds proper offline UX and prevents unnecessary network attempts

## Constraints

- `Network.framework` must be added to both iOS and macOS targets in `project.yml`
- `NetworkMonitor` should use `@Observable` to match existing service pattern
- The "Offline" indicator lives in Settings sync status row — no new UI component needed elsewhere
- Sync queue (pending entries) must NOT be lost — only skipped until connectivity returns
- No changes to SwiftData models or DynamoDB schema

## Open Questions

- None — approach is clear
