# Architectural Change Log — Auth, Photo Gallery & Soft-Delete Tombstone

**Date:** 2026-03-10
**Type:** New Subsystem + Data Model Change + Bug Fix
**Branch:** main (commits bce691f → 6ae94a9)

## Summary

Three architectural additions:
1. Full authentication subsystem replacing anonymous Cognito identity with email/password + Google OAuth
2. Soft-delete tombstone pattern on `DiaryEntry` to fix ghost-entry sync bug
3. Full-screen photo gallery component with gesture-based navigation

## Detailed Changes

### 1. Authentication Subsystem

**Before:** App used anonymous Cognito Identity Pool credentials (`GetId` + `GetCredentialsForIdentity` with no Logins map). No user accounts. All users shared the same Cognito identity pool anonymously.

**After:** Two-layer auth:
- **CognitoAuthService** now supports full User Pool auth (`InitiateAuth`, `SignUp`, `ConfirmSignUp`, `ForgotPassword`, `ConfirmForgotPassword`, `REFRESH_TOKEN_AUTH`) plus federated Google Sign-In
- **GoogleAuthService** (new) implements OAuth 2.0 Authorization Code + PKCE via `ASWebAuthenticationSession`, exchanges code for Google ID token, which is then federated through Cognito Identity Pool
- **SignInView** (new, 679 lines) provides all auth screens as a state machine (`AuthScreen` enum): sign-in, create account, verify email, forgot password, reset password
- **ForeverDiaryApp** now gates the entire app behind `cognitoAuth.isAuthenticated`; shows `SignInView` or `ContentView` accordingly

**New files:** `GoogleAuthService.swift`, `Views/Auth/SignInView.swift`
**Modified:** `CognitoAuthService.swift` (241 lines added), `ForeverDiaryApp.swift`, `AWSConfig.swift` (added User Pool + Google OAuth constants)

### 2. Soft-Delete Tombstone Pattern

**Before:** `SyncService.deleteEntry` hard-deleted the entry from SwiftData immediately. If the app synced before deletion could propagate, remote pull would re-create the entry (ghost entry bug).

**After:** `DiaryEntry` has a new `deletedAt: Date?` field. Deletion is a two-phase process:
- Phase 1 (local): Children (photos, check-ins) deleted immediately. Entry marked `deletedAt = .now, syncStatus = pending`.
- Phase 2 (remote): `pushPending` sends a tombstone PUT to DynamoDB with `deletedAt` field, then hard-deletes the entry locally.
- `upsertEntry` handles incoming tombstones: if `deletedAt >= local.updatedAt`, hard-delete local entry. If local has pending tombstone, skip remote upsert.
- All `@Query` predicates and `FetchDescriptor` calls filter `deletedAt == nil` to hide pending tombstones from the UI.

**Model change:** `DiaryEntry.deletedAt: Date? = nil` (SwiftData migration: additive, no migration required)

### 3. Photo Gallery

**Before:** Photos were displayed only as thumbnails in a grid. No full-screen viewer.

**After:** `PhotoGalleryView` (new) provides a full-screen photo gallery:
- `TabView` with `.page` style for swipe navigation
- `MagnificationGesture` for pinch-to-zoom (1x–4x bounds)
- `DragGesture` (downward only) to dismiss with opacity fade
- Dot indicator and X/counter overlay
- `lastScale` reset on tab change to prevent stale pinch reference

**New file:** `Views/Components/PhotoGalleryView.swift`

## Affected Components

| Component | Impact |
|-----------|--------|
| `ForeverDiaryApp` | Auth gate added; `startSync()` only called post-auth |
| `CognitoAuthService` | Full User Pool auth replaces anonymous-only flow |
| `GoogleAuthService` | New service; owned by `ForeverDiaryApp`, injected via environment |
| `SyncService.deleteEntry` | Soft-delete instead of hard-delete |
| `SyncService.pushPending` | Tombstone branch added; tombstones hard-deleted after push |
| `SyncService.upsertEntry` | Tombstone handling + pending-tombstone skip |
| `DiaryEntry` | New `deletedAt` field |
| `SignInView` | New; all auth screens |
| `PhotoGalleryView` | New; full-screen viewer |
| `SettingsView` | Account section (email display, sign-out) |
| `Lambda index.mjs` | `DeleteObjectsCommand` for S3 bulk deletion |
| All `@Query` predicates | `deletedAt == nil` filter added |

## Migration / Compatibility

- **SwiftData migration:** `deletedAt` field is additive with a default of `nil`. Existing installs load existing entries with `deletedAt == nil`, which is the correct default. No manual migration needed.
- **DynamoDB schema:** Tombstone records add a `deletedAt` attribute to existing entry items. The Lambda's `upsertEntry` equivalent (the pull path) reads `deletedAt` from items. Old Lambda builds that don't send `deletedAt` are unaffected.
- **Breaking change:** None. New auth replaces anonymous auth but all data remains accessible since Cognito Identity ID is persisted in Keychain. Authenticated users get the same identity pool identity.
