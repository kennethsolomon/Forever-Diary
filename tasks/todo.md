# Polling Optimization — Lightweight Check + Remote Update Toast

## Goal

Optimize periodic sync to use a lightweight change-check (saves bandwidth/battery), and show "Updated from another device" toast when remote changes arrive. Keep the existing 15-second polling interval.

## Plan

### Phase 1: Backend — Lightweight change-check endpoint

- [x] **1. Lambda: add `check=true` handler to GET /sync**
  - When `GET /sync?check=true&since=<timestamp>`, query DynamoDB with `Limit: 1` and `FilterExpression: updatedAt > :since`
  - Return `{ hasChanges: true/false, serverTime }` — no item data
  - Existing `GET /sync` (without `check=true`) unchanged
  - **Verify:** Deploy and confirm the endpoint works

### Phase 2: SyncService — Lightweight check + toast state

- [x] **2. SyncService: add `checkForChanges()` method**
  - Call `GET /sync?check=true&since=<lastSyncDate>` via `apiClient.get()`
  - Return `Bool` — true if server has newer data
  - Guard on `networkMonitor.isConnected` and `authService.isAuthenticated`

- [x] **3. SyncService: add `showRemoteUpdateToast` observable property**
  - `private(set) var showRemoteUpdateToast = false`
  - Set to `true` when `pullRemote()` applies at least one remote entry change
  - Auto-dismiss after 3 seconds via `Task.sleep`

- [x] **4. SyncService: update `pullRemote()` to track applied changes**
  - Add a counter that increments when `upsertEntry` actually updates local data (remoteUpdatedAt > local.updatedAt)
  - After `context.save()`, if counter > 0, trigger toast

- [x] **5. SyncService: update `startPeriodicSync` to use lightweight check**
  - Keep 15-second interval unchanged
  - In the loop: call `checkForChanges()` first — only call `syncAll()` if `hasChanges` is true
  - Falls back to full `syncAll()` if the check endpoint fails (backwards compat)

### Phase 3: Toast UI — iOS + macOS

- [x] **6. iOS HomeView: add "Updated from another device" toast**
  - Observe `syncService.showRemoteUpdateToast`
  - Overlay toast between divider and text editor (ZStack, top alignment)
  - HStack: SF Symbol `arrow.triangle.2.circlepath` + "Updated from another device"
  - Style: `surfaceCard` background, `borderSubtle` stroke, `cornerRadius: 10`, caption/rounded/medium font
  - Animate in with `.spring(response: 0.4, dampingFraction: 0.8)`, out with `.easeOut(duration: 0.3)`

- [x] **7. macOS EntryEditorView: add same toast**
  - Same design adapted for macOS layout (between header and location field)
  - Same animation and styling, using shared `syncService.showRemoteUpdateToast`

### Phase 4: Verify both platforms

- [x] **8. Build iOS target**
  - `xcodebuild build -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'`
  - Expected: BUILD SUCCEEDED

- [x] **9. Build macOS target**
  - `xcodebuild build -scheme ForeverDiaryMac -destination 'platform=macOS'`
  - Expected: BUILD SUCCEEDED

- [x] **10. Run tests**
  - `xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'`
  - Expected: All tests pass (111+)

## Verification

```bash
# Build iOS
xcodebuild build -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'

# Build macOS
xcodebuild build -scheme ForeverDiaryMac -destination 'platform=macOS'

# Run tests
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'
```

## Acceptance Criteria

1. [x] `GET /sync?check=true&since=<ts>` returns `{ hasChanges, serverTime }` with no item data
2. [x] Periodic sync uses lightweight check first, only does full sync when changes exist
3. [x] Polling interval stays at 15 seconds
4. [x] "Updated from another device" toast appears on iOS when remote data is applied
5. [x] Same toast appears on macOS
6. [x] Toast auto-dismisses after 3 seconds
7. [x] Both platforms build successfully
8. [x] All existing tests pass

## Risks/Unknowns

- **DynamoDB query cost**: `Limit: 1` with `FilterExpression` still scans, but single-user diary with ~1000 items is well within free tier. Total monthly cost: $0.
- **Backwards compatibility**: If the Lambda hasn't been redeployed with the `check=true` handler, `checkForChanges()` will fail and the periodic sync falls back to full `syncAll()`.

## Lessons Applied

- Tests will use `ModelContext(container)`, not `container.mainContext`
- No `@MainActor` on test classes
- No `@Attribute(.unique)` on any models
- Test host guarded with `NSClassFromString("XCTestCase")`
