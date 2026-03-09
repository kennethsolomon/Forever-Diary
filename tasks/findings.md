# Forever Diary v1 — Design Findings

## Problem Statement
Build an iPhone-first personal journaling app centered on a yearless calendar concept. Users browse Month -> Day and see a reverse-chronological stack of entries for that same date across years. The app should optimize for the fastest possible "write today" flow while preserving the reflective timeline view.

## Key Decisions

### Architecture
- **Single-package monolith** (Approach A) — one Xcode target, organized folders. Refactor into modules only if/when scale demands it.
- **iOS 17+** deployment target for full SwiftData support.
- **SwiftUI + SwiftData + CloudKit auto-sync** via `NSPersistentCloudKitContainer`.

### Data Models
- **DiaryEntry** — unique on `(monthDayKey, year)`. Owns freeform text, optional location, relationships to `CheckInValue` and `PhotoAsset`.
- **CheckInTemplate** — global reusable definitions (boolean, text, number). Managed in Settings.
- **CheckInValue** — per-entry values linking back to a template and entry.
- **PhotoAsset** — stores `imageData` + `thumbnailData` directly in SwiftData (app sandbox). JPEG 0.7 quality.

### Navigation
- 4-tab `TabView`: Home, Analytics, Calendar, Settings.
- `NavigationStack` per tab.
- EntryDetail is a shared screen with segmented control: Diary | Habit | Images.
- Calendar flow: Month grid -> Day grid -> Timeline (year cards, newest first).

### Photos
- **App sandbox storage** — photos copied into app, synced via CloudKit assets.
- Thumbnails generated at 300px for list views.
- `PhotosPicker` for library, `UIImagePickerController` for camera.

### Sync
- **SwiftData CloudKit auto-sync** — all reads/writes local, Apple handles merge/push.
- Fully offline capable.

### Location
- Auto-detect on entry creation via `CLLocationManager` + reverse geocode.
- Graceful fallback if permission denied — `locationText` stays nil, user can type manually.

### Default Habit Templates (first launch seed)
- Mood (text)
- Gratitude (text)
- Weight (number)
- Exercise (boolean)
- Sleep (number)

### Analytics
- Computed at read time via `@Query` + in-memory aggregation. No separate snapshot model.
- Week/Month/Year views for: entry completion rate, streaks, habit completion %, trend lines.
- Built with Swift Charts.

### Visual Design
- **Cool & minimal** palette: slate blue (#4A6FA5), soft gray (#8E9AAF), near-white bg (#F8F9FA).
- SF Pro typography with Dynamic Type.
- Cards with 12pt rounded corners, light shadows.
- SF Symbols for tab icons.

### Logo
- **Infinity + calendar** concept: continuous infinity loop in slate blue, one loop incorporates subtle calendar grid.
- SVG source, exported to AppIcon asset catalog.
- Clean single-weight stroke, works at all icon sizes.

## Chosen Approach & Rationale
Single-package monolith is the right call for a focused, personal diary app. It minimizes setup overhead, avoids premature abstraction, and lets SwiftData + CloudKit work with zero module-boundary friction. The app is intentionally niche — a diary, not a platform — so simplicity is a feature.

## Frontend Design (approved 2026-03-10)

### UX Changes from Brainstorming
1. **Write-first Home** — Home IS the writing surface, not a dashboard. Open app → cursor ready.
2. **Single scrollable entry** — text → habits → photos on one page. No segmented tabs.
3. **Horizontal month carousel** — swipe L/R for months instead of 3x4 grid.
4. **New York serif for diary text** — journal-like feel, distinct from rest of UI.

### Aesthetic: "Quiet Ink"
Cool slate tones, generous whitespace, serif diary text. Interface recedes so writing feels intimate.

### Color Palette
- Background: #F8F9FA (backgroundPrimary)
- Surface: #FFFFFF (surfaceCard)
- Text Primary: #2B2D42 (textPrimary)
- Text Secondary: #8E9AAF (textSecondary)
- Accent Blue: #4A6FA5 (accentSlate)
- Accent Bright: #5B8DEF (accentBright)
- Border: #E8ECF0 (borderSubtle)
- Habit Complete: #6BBF8A (habitComplete)
- Destructive: #E85D5D (destructive)
- Dark mode: #1A1B2E bg, #242538 surface, keep accent blue

### Typography
- Date header: SF Pro Rounded 28pt Semibold
- Year label: SF Pro Rounded 20pt Medium
- Diary text: New York (SF Serif) 17pt Regular
- Check-in labels: SF Pro Text 15pt Regular
- Tab bar: SF Pro Text 10pt Medium
- Caption: SF Pro Text 13pt Regular

### Key Components
- WriteView (Home): date header + full text editor + compact action bar (location, photos, habits)
- EntryDetail (from Calendar): scrollable — text → collapsible check-ins → photo grid
- MonthCarousel: TabView .page style, 12 pages, swipe horizontal
- DayRow: day number + dot indicators (dots = years with entries)
- YearCard: rounded 12pt card with year, weekday, location, 2-line preview, badges
- TimelineView: ScrollView of YearCards + optional Add Entry button
- PhotoGrid: LazyVGrid 3-col thumbnails

### Motion
- Year cards: staggered fade-in (0.05s delay per card)
- Check-in collapse: spring(response: 0.3, dampingFraction: 0.8)
- Photo add: scale + opacity transition
- Auto-save: subtle "Saved" text fade near date header

### Implementation Notes
- @FocusState for auto-focus text editor on Home
- .font(.serif) for New York on iOS 17+
- @Attribute(.externalStorage) on photo Data fields
- JPEG 0.7 compression, 300px thumbnails

## Open Questions
- None at this time. All v1 decisions are resolved.

## Out of Scope for v1
- iPad/Mac support
- Reminders/notifications
- Export/import
- Video/file attachments
- AI/sentiment analysis
- Android
- Multi-user/social features
- Monthly template overrides
