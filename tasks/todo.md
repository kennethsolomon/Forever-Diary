# Offline-First Auth Fix

## Goal
Fix the bug where losing internet connectivity redirects the user to the login screen. The app must remain fully usable offline (read + write diary entries); sync resumes automatically when connectivity returns. Both iOS and macOS targets are affected.

## Plan

### Phase 1 — Core service changes (shared by both targets)

- [ ] **1. Create `ForeverDiary/Services/NetworkMonitor.swift`**
  - `@Observable final class NetworkMonitor`
  - `private(set) var isConnected: Bool = true`
  - Uses `NWPathMonitor` on a dedicated `DispatchQueue`
  - `start()` begins monitoring; `stop()` cancels it
  - Updates `isConnected` on `DispatchQueue.main`
  - `import Network`
  - Verification: file compiles without errors

- [ ] **2. Add `Network.framework` to macOS target in `project.yml`**
  - Add `- sdk: Network.framework` under `ForeverDiaryMac.dependencies`
  - (iOS auto-links Network.framework; no iOS change needed)
  - Verification: `xcodegen generate` succeeds

- [ ] **3. Fix `CognitoAuthService.refreshIfNeeded()` — remove aggressive signOut**
  - Remove the `signOut()` call at line 220
  - Replace with `return` (credentials stay nil; sync will fail gracefully)
  - Add a comment: `// Network unavailable — stay authenticated, sync will retry`
  - Verification: method no longer calls `signOut()` on network failure

- [ ] **4. Inject `NetworkMonitor` into `SyncService`**
  - Add `private let networkMonitor: NetworkMonitor` property
  - Add `networkMonitor: NetworkMonitor` to `init()` signature
  - At top of `syncAll()`, add guard:
    ```swift
    guard networkMonitor.isConnected else {
        lastError = nil
        return
    }
    ```
  - Verification: `syncAll()` returns early when offline

### Phase 2 — iOS app wiring

- [ ] **5. Update `ForeverDiaryApp.swift` — instantiate and wire `NetworkMonitor`**
  - Add `let networkMonitor: NetworkMonitor` property
  - In `init()`: `networkMonitor = NetworkMonitor()`
  - Pass `networkMonitor` to `SyncService` init
  - In `scenePhase .active`: call `networkMonitor.start()`
  - In `scenePhase .background`: call `networkMonitor.stop()`
  - Pass to environment: `.environment(networkMonitor)` on `ContentView`
  - Verification: app builds; `NetworkMonitor` accessible in iOS view hierarchy

- [ ] **6. Update iOS `SettingsView` sync section — offline badge + button guard**
  - Add `@Environment(NetworkMonitor.self) private var networkMonitor`
  - Replace `Text("Active")` with offline/active conditional
  - Disable "Sync Now" button when `!networkMonitor.isConnected`
  - Verification: "Offline" shows in Settings Sync row when no internet

### Phase 3 — macOS app wiring

- [ ] **7. Update `ForeverDiaryMacApp.swift` — instantiate and wire `NetworkMonitor`**
  - Add `let networkMonitor: NetworkMonitor` property
  - In `init()`: `networkMonitor = NetworkMonitor()`, call `networkMonitor.start()`
  - Pass `networkMonitor` to `SyncService` init
  - Pass to environments on `WindowGroup` and `Settings` scenes
  - Verification: macOS app builds; `NetworkMonitor` in environment

- [ ] **8. Update macOS `SyncStatusView` — add offline state**
  - Add `let isConnected: Bool` parameter
  - Add offline icon (`wifi.slash`) and label (`"Offline"`) cases
  - Tint: `Color("textSecondary")` for offline (neutral, not error)
  - Verification: pill shows "Offline" when `isConnected == false`

- [ ] **9. Update `EntryEditorView.swift` — pass `isConnected` to `SyncStatusView`**
  - Add `@Environment(NetworkMonitor.self) private var networkMonitor`
  - Pass `isConnected: networkMonitor.isConnected` to `SyncStatusView`
  - Verification: sync pill in editor reflects offline state

- [ ] **10. Update macOS `SettingsMacView` `SyncTab` — offline badge + button guard**
  - Add `@Environment(NetworkMonitor.self) private var networkMonitor`
  - Show offline state; disable "Sync Now" when offline
  - Verification: macOS Settings Sync tab shows offline state correctly

### Phase 4 — Build verification

- [ ] **11. Run `xcodegen generate` + build both targets**
  - Verify zero build errors on iOS and macOS

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

## Acceptance Criteria

- [ ] App launched offline → user stays on the main diary screen (not redirected to login)
- [ ] Offline entries saved locally with `syncStatus = "pending"` — no data loss
- [ ] Settings shows "Offline" badge when no connectivity; "Sync Now" button disabled
- [ ] macOS sync pill shows "Offline" in editor toolbar and Settings
- [ ] When connectivity returns, next `syncAll()` resumes normally
- [ ] Explicit "Sign Out" still works correctly
- [ ] All existing tests pass

## Risks / Unknowns

- `NWPathMonitor` callback fires on background thread — must dispatch to main for `@Observable` updates (handled in `NetworkMonitor.start()`)
- macOS sandbox entitlement `com.apple.security.network.client` already present — no change needed
- `SyncService` init signature change requires updating both app files — tracked in steps 5 and 7
