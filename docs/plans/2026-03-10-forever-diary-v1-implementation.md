# Forever Diary v1 — Implementation Plan

## Phase 1: Project Setup & Logo
**Goal:** Xcode project scaffold, folder structure, app icon.

### Step 1.1 — Create Xcode project
- New SwiftUI App project: `ForeverDiary`
- iOS 17+ deployment target
- Enable CloudKit capability + iCloud entitlement
- Add background modes for remote notifications (CloudKit sync)

### Step 1.2 — Create folder structure
```
ForeverDiary/
├── App/
├── Models/
├── Views/
│   ├── Home/
│   ├── Calendar/
│   ├── Analytics/
│   ├── Settings/
│   └── Entry/
├── Services/
└── Assets.xcassets/
```

### Step 1.3 — Create SVG logo
- Infinity + calendar concept in slate blue (#4A6FA5)
- Export to Assets.xcassets/AppIcon

### Step 1.4 — Define color assets
- Add named colors to asset catalog: `PrimaryBlue`, `SecondaryGray`, `BackgroundLight`, `TextPrimary`, `TextSecondary`, `AccentBlue`

---

## Phase 2: Data Models
**Goal:** All SwiftData models compiled and ready.

### Step 2.1 — DiaryEntry model
- `@Model` class with `monthDayKey` (String), `year` (Int), `date` (Date), `weekday` (String), `diaryText` (String), `locationText` (String?), `createdAt` (Date), `updatedAt` (Date)
- `@Relationship` to `[CheckInValue]` and `[PhotoAsset]` with cascade delete
- Unique constraint on `(monthDayKey, year)` via `#Unique`

### Step 2.2 — CheckInTemplate model
- `@Model` class with `id` (UUID), `label` (String), `type` (enum: boolean/text/number), `isActive` (Bool), `sortOrder` (Int)

### Step 2.3 — CheckInValue model
- `@Model` class with `id` (UUID), `boolValue` (Bool?), `textValue` (String?), `numberValue` (Double?)
- `@Relationship` back to `DiaryEntry` and `CheckInTemplate`

### Step 2.4 — PhotoAsset model
- `@Model` class with `id` (UUID), `imageData` (Data), `thumbnailData` (Data), `createdAt` (Date)
- `@Relationship` back to `DiaryEntry`

### Step 2.5 — ModelContainer configuration
- Configure in `ForeverDiaryApp.swift` with `cloudKitDatabase: .automatic`
- Register all models in the schema

---

## Phase 3: Tab Shell & Navigation
**Goal:** 4-tab layout with NavigationStack per tab, all screens stubbed.

### Step 3.1 — Root TabView
- `ContentView` with TabView: Home, Analytics, Calendar, Settings
- SF Symbols: `house.fill`, `chart.bar.fill`, `calendar`, `gearshape.fill`

### Step 3.2 — Stub all screen views
- `HomeView`, `AnalyticsView`, `CalendarView`, `SettingsView`
- Placeholder text in each, confirm navigation works

---

## Phase 4: Home Screen
**Goal:** Today-first experience with quick entry access.

### Step 4.1 — HomeView layout
- Display today's date (formatted), current year
- Query for today's `DiaryEntry` — show "Add Entry" or "Edit Entry" accordingly
- Quick photo action button
- Compact habit/check-in summary (if entry exists)

### Step 4.2 — Navigation to EntryDetail
- Tap Add/Edit → present `EntryDetailView` as full-screen sheet
- Pass today's `monthDayKey` and `year`

---

## Phase 5: Entry Detail Screen
**Goal:** The core writing/habit/photo experience.

### Step 5.1 — EntryDetailView shell
- Segmented control: Diary | Habit | Images
- Save/dismiss controls
- Create or fetch existing `DiaryEntry` for the given `(monthDayKey, year)`

### Step 5.2 — Diary tab
- `TextEditor` for freeform diary text
- Auto-save on dismiss or explicit save button
- Location display/edit field

### Step 5.3 — Habit tab
- Query active `CheckInTemplate`s sorted by `sortOrder`
- Render appropriate input per type: Toggle (boolean), TextField (text), number field (number)
- Create/update `CheckInValue` for each template on this entry

### Step 5.4 — Images tab
- Grid of existing photos (thumbnails)
- Add button → `PhotosPicker` or camera
- On selection: compress to JPEG 0.7, generate 300px thumbnail, save as `PhotoAsset`
- Tap photo to view full-size
- Delete photo with confirmation

---

## Phase 6: Calendar (Yearless Browser)
**Goal:** Month → Day → Timeline navigation.

### Step 6.1 — Month grid
- `CalendarView` shows 12 months in a grid (3x4 or 4x3)
- Each month cell shows name + entry count indicator for that month

### Step 6.2 — Day grid
- Tap month → push `DayGridView` showing days 1–N for that month
- Highlight days that have entries (any year)
- Handle variable month lengths (28–31)

### Step 6.3 — Timeline view
- Tap day → push `TimelineView` for that `monthDayKey`
- If current year has no entry: show primary "Add Entry" button at top
- List of year cards, newest first
- Each card: year, weekday, location, 2-line text preview, photo count badge, habit completion summary

### Step 6.4 — Timeline to EntryDetail
- Tap year card → push `EntryDetailView` in edit mode
- Tap "Add Entry" → present `EntryDetailView` for current year

---

## Phase 7: Settings
**Goal:** Habit template management and app info.

### Step 7.1 — SettingsView layout
- Section: Habit Templates
- Section: iCloud Sync status
- Section: About (version, etc.)

### Step 7.2 — Habit template management
- List of templates with edit/delete/reorder
- Add new template: label, type picker, active toggle
- Reorder via `EditButton` + `.onMove`
- Delete with swipe or edit mode

---

## Phase 8: Analytics
**Goal:** Consistency and habit tracking visualizations.

### Step 8.1 — AnalyticsView layout
- Segment picker: Week / Month / Year
- Cards for: entry completion rate, current streak, longest streak

### Step 8.2 — Entry completion chart
- Bar or ring chart (Swift Charts) showing entries per day/week/month

### Step 8.3 — Streak calculation
- Count consecutive days backward from today with entries
- Track longest streak across all time

### Step 8.4 — Habit completion trends
- Per-template completion % over the selected period
- Line chart or bar chart via Swift Charts

---

## Phase 9: Location Service
**Goal:** Auto-detect location on entry creation.

### Step 9.1 — LocationService
- `CLLocationManager` wrapper using `@Observable`
- Request when-in-use authorization
- Single location request on entry creation
- Reverse geocode to city/area string
- Graceful fallback: if denied or failed, return nil silently

---

## Phase 10: First Launch & Polish
**Goal:** Seed data, polish, edge cases.

### Step 10.1 — First launch seed
- Detect first launch (no templates exist)
- Create default templates: Mood (text), Gratitude (text), Weight (number), Exercise (boolean), Sleep (number)

### Step 10.2 — Empty states
- Home: welcoming message when no entries exist yet
- Calendar: subtle indicators for months/days with no entries
- Analytics: placeholder when insufficient data

### Step 10.3 — Permission handling
- Photo library: handle denied state gracefully in Images tab
- Camera: handle unavailable/denied
- Location: handle denied/restricted — show manual input

### Step 10.4 — Delete entry
- Swipe-to-delete on year cards in timeline
- Confirmation alert, cascade delete check-in values + photos

---

## Dependency Order

```
Phase 1 (Setup + Logo)
  └→ Phase 2 (Models)
       └→ Phase 3 (Tab Shell)
            ├→ Phase 4 (Home) → Phase 5 (Entry Detail)
            ├→ Phase 6 (Calendar) ─── uses Entry Detail from Phase 5
            ├→ Phase 7 (Settings)
            └→ Phase 8 (Analytics)
       └→ Phase 9 (Location) ─── used by Phase 5
  └→ Phase 10 (Polish) ─── after all features
```

## Estimated Phases: 10 | Steps: ~25
