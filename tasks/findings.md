# Polling Optimization — Near-Instant Cross-Device Sync

## Problem Statement

After Phase 1 sync fixes (pull-before-push, skip-unchanged guards), cross-device sync is correct but slow when both apps are open simultaneously. The 15-second periodic sync interval means edits on one device take up to 15 seconds to appear on the other. There is no visual feedback when remote changes arrive.

## Scenarios

| Scenario | Current (Phase 1) | After Approach A |
|----------|-------------------|------------------|
| App closed, open later | Works correctly (pull-first) | Same — no change needed |
| App open, other device edits | Up to 15s delay, no notification | Up to 15s delay + "Updated" toast + cheaper polls |
| App backgrounded, other device edits | Syncs on next foreground | Same — no change needed |

## Chosen Approach: Polling Optimization (Approach A)

No APNS — no paid Apple Developer account required.

### Changes

1. **Lightweight change-check endpoint** — New `GET /sync?check=true` (or `HEAD /sync`) Lambda handler that returns only `{ hasChanges: bool, serverTime }` based on whether any items have `updatedAt > lastSyncDate`. Cheap query, minimal bandwidth.

2. **Keep 15s polling, use lightweight check** — Keep existing 15-second interval. Each poll calls the lightweight check first — only triggers full `syncAll()` if `hasChanges` is true. Saves bandwidth and battery without increasing request frequency.

3. **"Updated from another device" toast** — When `pullRemote()` finds and applies newer remote data, show a brief toast/banner on both iOS and macOS. Visible confirmation that sync happened.

4. **Both platforms** — iOS (`ForeverDiaryApp`) and macOS (`ForeverDiaryMacApp`) get the same polling interval and toast behavior.

### What Users See

- Edits on one device appear on the other within up to 15 seconds (while both are open) — same interval, but cheaper per poll
- A brief "Updated from another device" message confirms the sync
- No change to offline-first behavior — local edits save immediately
- No change to app-open behavior — full sync still runs on foreground

### Constraints

- No paid Apple Developer account — no APNS, no background sync
- Must not increase battery/network usage — lightweight check reduces bandwidth per poll, interval stays at 15s
- Must work on both iOS 17+ and macOS 14+
- Lessons: no `@Attribute(.unique)`, use `ModelContext(container)` in tests, guard test host init

## Affected Files

- `aws/lambda/index.mjs` — New lightweight change-check handler
- `ForeverDiary/Services/SyncService.swift` — Polling interval, lightweight check, toast trigger
- `ForeverDiary/App/ForeverDiaryApp.swift` — Updated periodic sync interval
- `ForeverDiaryMac/App/ForeverDiaryMacApp.swift` — Same
- `ForeverDiary/Views/Home/HomeView.swift` — Toast UI (iOS)
- `ForeverDiaryMac/Views/Editor/EntryEditorView.swift` — Toast UI (macOS)

## Open Questions

- None — straightforward polling optimization
