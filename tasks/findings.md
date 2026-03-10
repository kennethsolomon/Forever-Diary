# Forever Diary — Calendar UI + Theme + View Mode Redesign

## Problem Statement
The calendar tab is a flat vertical list of day numbers with dots — no visual richness, no photos, no real calendar layout. The app also lacks a proper theme system and a view/write mode toggle for diary entries.

## Scope — Three Features

### Feature A: Calendar Grid Redesign
**Goal:** Replace the flat day list with a photo-rich calendar grid.

- **Layout:** 7-column calendar grid with proper weekday alignment (day 1 on correct column)
- **Month header:** Month name centered at top, no day-of-week column labels
- **Month navigation:** Vertical scroll through all 12 months (replace paged TabView)
- **Day cells:**
  - No photos: plain day number
  - 1 photo: full circular thumbnail with day number overlaid in white + drop shadow
  - 2–3 photos: circle divided into halves/thirds showing different thumbnails
  - 4+ photos: quad-divided circle with count badge
  - Photos aggregate across all years for that monthDayKey
- **Today indicator:** Highlighted number (accent color or accent ring)
- **Tap interaction:** Inline popover/sheet with compact summary:
  - Photo grid + text previews per year entry
  - Tap an entry in the popover to navigate to full EntryDetailView
  - Replaces the current push-to-DayTimelineView navigation for initial tap

### Feature B: Theme System
**Goal:** Clean, readable theme with dark/light toggle.

- **Dark mode palette:**
  - Background primary: #222831
  - Surface/card: #393E46
  - Accent: #00ADB5 (teal)
  - Text primary: #EEEEEE
- **Light mode palette:**
  - Background primary: white
  - Surface/card: light gray or white with subtle shadow
  - Accent: #00ADB5 (same teal)
  - Text primary: dark/black
- **Toggle:** Settings page — button/toggle to switch dark/light
- **Implementation:** Update existing color assets or replace with a theme system that respects the toggle
- Clean, minimal, highly readable

### Feature C: View/Write Mode Toggle
**Goal:** Apple Notes-style read/write behavior on Home and EntryDetailView.

- **Button:** Upper-right corner, toggles between view and write mode
- **Write mode (default):** Current behavior — TextEditor, keyboard, editable
- **View mode:** Diary text rendered as **markdown** (supports future markdown export)
  - No cursor, no keyboard
  - Tap anywhere on the text area → switches back to write mode automatically
- **Applies to:** HomeView and EntryDetailView

## Key Decisions

1. **Vertical scroll for months** instead of paged TabView — eliminates gesture conflicts, more natural browsing
2. **Collage circle** for multi-photo days — matches user's reference screenshot
3. **Inline popover** instead of push navigation — reduces tap depth (2 taps to entry instead of 3)
4. **Markdown rendering** in view mode — prepares for future markdown export feature
5. **Theme toggle in Settings** — simple, not cluttering other views
6. **Thumbnails are 300x300 JPEG** (`PhotoAsset.thumbnailData`) — sufficient for small circular grid cells

## Files Likely Affected

### Calendar (Feature A)
- `ForeverDiary/Views/Calendar/CalendarBrowserView.swift` — full rewrite (grid, vertical scroll, collage cells)
- `ForeverDiary/Views/Calendar/TimelineView.swift` — may be repurposed or replaced by popover content
- Possibly new: popover/sheet view for day summary

### Theme (Feature B)
- `Assets.xcassets/` — update color sets (backgroundPrimary, surfaceCard, textPrimary, textSecondary, accentBright, accentSlate)
- `ForeverDiary/Views/Settings/SettingsView.swift` — add theme toggle
- Possibly new: theme manager/service or AppStorage-based preference

### View/Write Mode (Feature C)
- `ForeverDiary/Views/Home/HomeView.swift` — add toggle button, view mode with markdown rendering
- `ForeverDiary/Views/Entry/EntryDetailView.swift` — same toggle + markdown rendering
- Markdown rendering: use `AttributedString` with markdown init (built into iOS 15+) or a lightweight approach

## Design Constraints (from lessons.md)
- No `@Attribute(.unique)` in SwiftData models
- Test containers must use `ModelContext(container)` not `container.mainContext`
- Test host guard for CloudKit in ForeverDiaryApp

## Open Questions
- None — direction is locked in.
