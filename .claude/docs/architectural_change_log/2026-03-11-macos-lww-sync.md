# Architectural Change: macOS Target + LWW Sync Protocol

**Date:** 2026-03-11
**Branch:** feat/macos-parity-and-lww-sync
**Type:** New Platform Target + Protocol Change + Schema Change

## Summary

Three significant architectural changes shipped together: (1) a macOS companion app with full iOS feature parity, (2) a server-side last-write-wins sync protocol replacing client-controlled batch writes, and (3) soft-delete tombstone support on CheckInTemplate and CheckInValue models.

## Detailed Changes

### 1. macOS Target (ForeverDiaryMac)

**What changed:** Added a second XcodeGen target `ForeverDiaryMac` sharing all source files with the iOS app via `ForeverDiary/` source references. The macOS app uses a 3-column `NavigationSplitView` layout while iOS retains its existing tab-based navigation.

**Before:** iOS-only SwiftUI app.
**After:** Dual-platform app; shared model, service, and view code between iOS and macOS targets. Platform-specific layouts diverge only at the top-level navigation container.

**Affected components:** `project.yml`, all Views (conditional `#if os(macOS)`), `ForeverDiary.entitlements`

### 2. Server-Side LWW via DynamoDB ConditionalExpression

**What changed:** Sync push (`POST /sync`) moved from `BatchWriteItem` (unconditional upsert) to `UpdateItem` with a `ConditionExpression`:

```
attribute_not_exists(#updatedAt) OR #updatedAt <= :newUpdatedAt
```

A `ConditionalCheckFailedException` means the server already holds a newer version; the client silently skips that item and reconciles on the next pull.

**Before:** Client sent `BatchWriteItem` which overwrote server state regardless of timestamp. Race condition: concurrent writes from two devices would corrupt data based on network ordering alone.

**After:** Server enforces LWW — the most recently-dated write wins regardless of arrival order. `written`/`skipped`/`deleted` counters returned to client for observability.

**Protocol addition:** Both push and pull responses now include `serverTime` (ISO 8601) so clients can detect large clock skew.

**Affected components:** `aws/lambda/index.mjs` (`handleSyncPush`, new `buildUpdateParams`), `ForeverDiary/Services/APIClient.swift`

### 3. Soft-Delete Tombstone on CheckInTemplate and CheckInValue

**What changed:** `CheckInTemplate` and `CheckInValue` SwiftData models gained `updatedAt: Date` and `deletedAt: Date?` fields, matching the existing pattern on `DiaryEntry`.

**Before:** Deleted templates and check-in values were hard-deleted locally and the deletion was not propagated to other devices via sync.

**After:** Template deletion sets `deletedAt` + `updatedAt` and pushes a tombstone record to DynamoDB. Remote pulls that see `deletedAt` mark the local record as deleted. A startup `deduplicateTemplates()` and `deduplicateCheckInValues()` pass cleans any sync-induced duplicates.

**Affected components:** `ForeverDiary/Models/CheckInTemplate.swift`, `ForeverDiary/Models/CheckInValue.swift`, `ForeverDiary/Services/SyncService.swift`

### 4. @Query Migration in HomeView and EntryDetailView

**What changed:** Both views replaced the manual `loadEntry()` + `@State var entry` pattern with a SwiftData `@Query` predicate. This means SwiftUI automatically re-renders when a remote sync updates the underlying store — no manual reload needed.

**Before:** Entry loaded once on `onAppear`; remote sync changes were invisible until navigation or refresh.

**After:** `@Query` observes the SwiftData store; remote-synced changes appear in the UI immediately.

**Affected components:** `ForeverDiary/Views/Home/HomeView.swift`, `ForeverDiary/Views/Entry/EntryDetailView.swift`

## Migration / Compatibility

- **DynamoDB:** No schema migration needed; `UpdateItem` is compatible with existing items. New items get `updatedAt` set on first write.
- **Lambda:** Deploy `aws/lambda/index.mjs` before shipping the iOS update. Old clients sending `BatchWriteItem` format will still work via the `POST /sync` endpoint (they'll receive a 400 if format is wrong).
- **SwiftData:** `updatedAt`/`deletedAt` on `CheckInTemplate` and `CheckInValue` use default values; no migration required for existing local databases.
- **macOS:** Separate bundle ID (`com.foreverdiary.mac`) — independent install, shared iCloud/DynamoDB identity.
