# Forever Diary — UI Polish + Sign in with Apple

## Problem Statement
Four improvements to the iOS app:
1. Remove the view/write mode toggle (eye icon) from Home and EntryDetail — it's unwanted
2. Photo viewer is broken (not centered, image cut off) — needs a full paginated gallery
3. Calendar day cells (circles) don't match the aesthetic — needs photo cards with stacked deck effect
4. No real accounts — users can't sign in, data is device-bound (anonymous Cognito)

## Scope — Four Features

### Feature A: Remove View/Write Mode Toggle
**Goal:** Delete the eye icon and all related code.

- Remove `isViewMode` state from `HomeView` and `EntryDetailView`
- Remove toolbar `Button` (eye / square.and.pencil icon) from both views
- Remove `MarkdownTextView` render branches from both `textEditor` and `diarySection`
- Delete `MarkdownTextView.swift` (zero usages after removal)
- Remove `MarkdownTests.swift` (only tests the deleted component)
- Remove `isTextEditorFocused` toggle-on-mode-switch side effects in `HomeView`

### Feature B: Full Paginated Photo Gallery Viewer
**Goal:** Replace the broken fullscreen single-photo view with a proper swipe-through gallery.

- Root cause: `ZStack(alignment: .topTrailing)` + `.ignoresSafeArea()` on image
- New `PhotoGalleryView`: full-screen, black bg, swipe left/right through all entry photos
- Entry point: tap any photo thumbnail → opens gallery at that photo's index
- `X of N` counter at top (or pagination dots at bottom)
- Pinch-to-zoom on current photo
- Swipe down to dismiss (with velocity threshold)
- Applies to: `EntryDetailView` (primary), and `YearSummaryCard` thumbnails (also tappable)
- Improve `YearSummaryCard` photo thumbnails: larger tiles (64×64), not the current 40×40 strip

### Feature C: Calendar Day Cards + Stacked Display
**Goal:** Replace circular day cells with portrait-ratio photo cards; multi-entry/photo days show a stacked deck.

- **Shape:** `RoundedRectangle` card, portrait aspect ratio ~3:4
- **Single entry / no photo:** Plain card with day number, teal accent ring for today
- **Single photo:** Card with photo background, day number overlaid in white
- **2+ entries or photos:** Stacked deck using `ZStack`
  - 2–3 background cards slightly offset (y +4–8px) and rotated (±2–4°)
  - Top card shows the most recent/primary photo
  - Small count badge (number of entries or total photos)
- Remove all `Circle()` / `clipShape(Circle())` from `DayCell`
- Keep `ScaleButtonStyle` press animation

### Feature D: Sign in with Apple + Account System
**Goal:** Replace anonymous Cognito with Apple-authenticated identity. Account required — no guest mode.

**Auth flow:**
1. App launch → check Keychain for authenticated session → if not found, show `SignInView`
2. `SignInView`: centered "Sign in with Apple" button (ASAuthorizationAppleIDProvider)
3. Apple returns `identityToken` (JWT) → pass to Cognito Identity Pool as Apple Login provider
4. Cognito returns stable authenticated `identityId` (linked to Apple account, stable across devices)
5. Store `identityId` + display name in Keychain
6. App unlocks — proceed to main `ContentView`

**Migration (anonymous → authenticated):**
- Cognito Identity Linking: pass the stored anonymous `identityId` alongside the Apple token in `GetId`
- Cognito merges anonymous → authenticated identity, returns the same IdentityId
- All DynamoDB data (keyed by old IdentityId) remains intact — zero data movement needed
- One-time migration on first sign-in; subsequent sign-ins skip this

**New files:**
- `ForeverDiary/Views/Auth/SignInView.swift` — Sign in with Apple screen
- `ForeverDiary/Services/AppleAuthService.swift` — ASAuthorizationAppleIDProvider wrapper

**Modified files:**
- `ForeverDiary/Services/CognitoAuthService.swift` — add `authenticateWithApple(identityToken:)`, identity linking
- `ForeverDiary/App/ForeverDiaryApp.swift` — auth gate: `SignInView` if not authenticated, else `ContentView`
- `ForeverDiary/Views/Settings/SettingsView.swift` — Account section: show Apple display name, Sign Out button

## Key Decisions

1. **View mode removed entirely** — simplifies both views, no markdown render path
2. **Full paginated gallery** — swipe between photos, pinch-to-zoom, swipe-down dismiss
3. **Stacked card deck** — portrait cards, ZStack offset + slight rotation for multi-entry days
4. **Cognito Identity Linking** — anonymous IdentityId upgraded to authenticated in-place; no Lambda migration needed
5. **Account required** — no guest mode; Sign in with Apple mandatory on first launch
6. **Apple identity token → Cognito** — use `appleid.apple.com` as the Cognito Identity Pool login provider key

## Files Affected

### Feature A (View Mode Removal)
- `ForeverDiary/Views/Home/HomeView.swift`
- `ForeverDiary/Views/Entry/EntryDetailView.swift`
- `ForeverDiary/Views/Components/MarkdownTextView.swift` — delete
- `ForeverDiaryTests/MarkdownTests.swift` — delete

### Feature B (Photo Gallery)
- `ForeverDiary/Views/Entry/EntryDetailView.swift` — replace `fullScreenCover` with gallery
- `ForeverDiary/Views/Calendar/TimelineView.swift` — improve `YearSummaryCard` photo thumbnails
- New: `ForeverDiary/Views/Components/PhotoGalleryView.swift`

### Feature C (Calendar Cards)
- `ForeverDiary/Views/Calendar/CalendarBrowserView.swift` — rewrite `DayCell`

### Feature D (Auth)
- `ForeverDiary/App/ForeverDiaryApp.swift`
- `ForeverDiary/Services/CognitoAuthService.swift`
- `ForeverDiary/Views/Settings/SettingsView.swift`
- New: `ForeverDiary/Views/Auth/SignInView.swift`
- New: `ForeverDiary/Services/AppleAuthService.swift`

## Design Constraints (from lessons.md)
- No `@Attribute(.unique)` in SwiftData models
- Test containers must use `ModelContext(container)` not `container.mainContext`
- Test host guard for CloudKit in ForeverDiaryApp (extend to skip auth services too)

## Open Questions
- None — direction is locked in.
