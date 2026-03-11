# Sync Race Condition — Stale Local Data Overwrites Remote on App Open

## Problem Statement

When a user edits a diary entry on macOS, closes the app (data syncs to cloud), then opens the iOS app, the iOS app overwrites the macOS edits with its stale local version. The same bug exists in reverse (iOS → macOS).

## Root Cause

`HomeView.onAppear` (iOS) and `EntryEditorView.onAppear` (macOS) load the old local entry text into `@State var diaryText`. This triggers `onChange(of: diaryText)` → `debounceSave()` → `saveEntry()`, which sets `updatedAt = .now` and `syncStatus = "pending"` — even though the user didn't type anything.

Race sequence:
1. App opens → `onAppear` loads old local text into `diaryText`
2. `onChange(of: diaryText)` fires ("" → "old text" is a change)
3. `debounceSave()` starts (saveTask is now non-nil, 1s timer)
4. `syncAll()` → `pullRemote()` fetches newer macOS data, updates entry model
5. `onChange(of: entry?.diaryText)` fires, but `guard saveTask == nil` blocks it (line 61/117)
6. 1 second later: `saveEntry()` writes OLD text with FRESH `updatedAt = .now`, `syncStatus = "pending"`
7. Next sync: `pushPending()` sends stale text with the newest timestamp → overwrites cloud
8. Other device pulls → LWW picks the stale-but-newer entry → data loss

Additionally, `syncAll()` runs push-before-pull, so any locally pending items get pushed before the device has a chance to learn about newer remote changes.

## Affected Files

- `ForeverDiary/Views/Home/HomeView.swift` — iOS (lines 56, 59-63, 116-118, 192-225)
- `ForeverDiaryMac/Views/Editor/EntryEditorView.swift` — macOS (lines 81, 111-117, 404-427)
- `ForeverDiary/Services/SyncService.swift` — push-before-pull order (line 266-268)

## Chosen Approach: A + C

### Phase 1: Bug Fix (A + C)

**A — Skip save if text unchanged:**
- In `saveEntry()` (iOS) and `debounceSave()` (macOS), compare new text with `entry.diaryText` before saving
- If identical, return early — no `updatedAt` bump, no `syncStatus = "pending"`
- This directly prevents `onAppear` from creating spurious pending saves
- Apply the same guard to `locationText` saves

**C — Pull-before-push + cancel debounce on remote update:**
- Reorder `syncAll()` to run `pullRemote()` before `pushPending()`
- LWW guards in `upsertEntry()` already prevent overwriting newer local data, so pull-first is safe
- In `onChange(of: entry?.diaryText)`, cancel `saveTask` and update `diaryText` when remote data arrives (instead of silently skipping)
- This ensures the UI always reflects the latest data from any device

### Phase 2: Push-Triggered Sync (future)

**APNS silent push notification after a device pushes:**
- After `pushPending()` succeeds, send a silent push via APNS to other devices
- Receiving device calls `syncAll()` immediately instead of waiting for the 15s periodic timer
- Requires: APNS certificate/key in Lambda, device token registration endpoint, `application(_:didReceiveRemoteNotification:)` handler
- Reduces sync delay from up to 15 seconds to near-instant
- Scoped as a separate feature — not blocking for the bug fix

## Constraints

- Both iOS and macOS editors must be fixed (same pattern, both affected)
- Must not break real-time typing — only skip save when text is truly identical
- `onChange(of: entry?.diaryText)` must still cancel debounce and update UI on remote changes
- Lessons learned: no `@Attribute(.unique)`, use `ModelContext(container)` in tests, guard test host init
- Security: no new OWASP surface introduced by reordering push/pull

## Open Questions

- None for Phase 1
- Phase 2 (APNS): exact Lambda implementation and device token storage TBD during that planning cycle
