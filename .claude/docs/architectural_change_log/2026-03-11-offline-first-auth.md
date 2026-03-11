# Architectural Change: Offline-First Auth + NetworkMonitor Service

**Date:** 2026-03-11
**Branch:** feat/macos-parity-and-lww-sync
**Type:** New Service + Auth Behavior Change

## Summary

Two coordinated changes fix the root cause of users being redirected to the login screen when offline: (1) `CognitoAuthService.refreshIfNeeded()` no longer calls `signOut()` when all network refresh paths fail, and (2) a new `NetworkMonitor` service (wrapping `NWPathMonitor`) provides a reachability guard that prevents `SyncService.syncAll()` from running at all when the device has no connectivity.

## Detailed Changes

### 1. CognitoAuthService — Remove signOut() on Network Failure

**What changed:** The final fallback path in `refreshIfNeeded()` previously called `signOut()` when all token refresh attempts failed (network timeout, AWS unreachable, etc.). This treated network errors as auth failures, forcing the user back to the login screen.

**Before:**
```swift
// All refresh paths failed — sign out
signOut()
```

**After:**
```swift
// Network unavailable — stay authenticated, sync will retry when connectivity returns
return
```

**Affected components:** `CognitoAuthService.swift:219`

**Trade-off:** If credentials are genuinely revoked (not a network error), the user stays "authenticated" but the next sync attempt will fail with a 401/403 and surface an error in the UI. They will not be auto-signed-out on credential revocation. This is the accepted offline-first trade-off — staying in the app is preferred over losing in-progress diary work.

### 2. NetworkMonitor — NWPathMonitor Reachability Service

**What changed:** New `NetworkMonitor` `@Observable` class wrapping Apple's `NWPathMonitor` from `Network.framework`. Exposes `isConnected: Bool` (defaults to `true` optimistically). `SyncService.syncAll()` guards on `networkMonitor.isConnected` before attempting any network operations.

**Before:** `SyncService.syncAll()` attempted network operations unconditionally; failures surfaced as error messages.

**After:**
```
App launch → NetworkMonitor.start() → NWPathMonitor fires path update
  → isConnected = false (offline)
  → syncAll() returns immediately (no network ops, no error shown)
  → User writes entries normally into SwiftData
  → Connectivity restored → isConnected = true → next sync succeeds
```

**iOS lifecycle:** `start()` called on `scenePhase == .active`; `stop()` called on `scenePhase == .background`. `start()` is idempotent (guarded by `monitor == nil`).

**macOS lifecycle:** `start()` called in `ForeverDiaryMacApp.init()` and runs for the app's lifetime (macOS has no background lifecycle equivalent).

**Network.framework** added to `ForeverDiaryMac` dependencies in `project.yml` (`Network.framework` was already available to the iOS target via the SDK).

**Affected components:** `NetworkMonitor.swift` (new), `SyncService.swift`, `ForeverDiaryApp.swift`, `ForeverDiaryMacApp.swift`, `project.yml`

## Offline UI

Both platforms show an offline state in the Sync UI when `isConnected == false`:
- **iOS Settings:** "Offline" text badge; "Sync Now" button disabled
- **macOS SyncStatusView:** `wifi.slash` SF Symbol, "Offline" label, muted tint
- **macOS Settings → Sync tab:** Same offline icon/label; error display suppressed; "Sync Now" disabled

## Migration / Compatibility

No schema changes. No API changes. No breaking changes for existing users. The `NetworkMonitor` is a new optional service — removing it would revert to the previous (always-attempt-sync) behavior.
