# Sync Race Condition Fix — Pull-Before-Push + Skip Unchanged Saves

## Goal

Fix the bug where opening the app on one device overwrites newer cloud data from another device, caused by `onAppear` triggering a spurious save with a fresh timestamp.

## Plan

### Phase 1: Fix A — Skip save if text unchanged

- [x] **1. iOS HomeView: guard saveEntry against unchanged text**
- [x] **2. macOS EntryEditorView: guard debounceSave against unchanged text**
- [x] **3. macOS EntryEditorView: guard locationText save against unchanged value**

### Phase 2: Fix C — Pull-before-push + cancel debounce on remote update

- [x] **4. Reorder syncAll: pull before push**
- [x] **5. iOS HomeView: cancel debounce on remote text update**
- [x] **6. macOS EntryEditorView: cancel debounce on remote text update**

### Phase 3: Verify both platforms build

- [x] **7. Build iOS target** — BUILD SUCCEEDED (iPhone 16e)
- [x] **8. Build macOS target** — BUILD SUCCEEDED
- [x] **9. Run tests** — All tests pass

## Acceptance Criteria

1. [x] `saveEntry()` (iOS) does NOT set `updatedAt`/`syncStatus` when text is identical
2. [x] `debounceSave()` (macOS) does NOT set `updatedAt`/`syncStatus` when text is identical
3. [x] `syncAll()` calls `pullRemote()` before `pushPending()`
4. [x] `onChange(of: entry?.diaryText)` cancels in-flight `saveTask` on both platforms
5. [x] Both iOS and macOS targets build successfully
6. [x] Existing tests pass
