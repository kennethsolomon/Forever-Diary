# Calendar UI + Theme + View Mode Redesign

## Goal
Redesign the calendar tab as a photo-rich 7-column grid with collage circles, add a dark/light theme system with user toggle, and implement Apple Notes-style view/write mode with markdown rendering on Home and EntryDetailView.

## Lessons Applied
- No `@Attribute(.unique)` on any model fields
- Tests use `ModelContext(container)`, not `container.mainContext`
- Test host guard (`NSClassFromString("XCTestCase")`) skips network services

---

## Phase 1: Theme System (Feature B) — do first so all subsequent UI uses new colors

- [x] 1.1 Update color asset `backgroundPrimary` — dark: #222831, light: #FFFFFF
- [x] 1.2 Update color asset `surfaceCard` — dark: #393E46, light: #F5F6F8
- [x] 1.3 Update color asset `accentBright` — dark+light: #00ADB5
- [x] 1.4 Update color asset `accentSlate` — dark+light: #008B92
- [x] 1.5 Update color asset `textPrimary` — dark: #EEEEEE, light: #222831
- [x] 1.6 Update color asset `textSecondary` — dark: #9EA4AB, light: #6B7280
- [x] 1.7 Update color asset `borderSubtle` — dark: #4A5058, light: #E5E7EB
- [x] 1.8 Add `@AppStorage("appTheme")` to `ContentView.swift` with `.preferredColorScheme()` — options: system/light/dark
- [x] 1.9 Add "Appearance" section to `SettingsView.swift` with segmented picker (System / Light / Dark)
- [x] 1.10 Update tab bar tint in `ContentView` to use `accentBright`

## Phase 2: Calendar Grid (Feature A)

- [x] 2.1 Rewrite `CalendarBrowserView.swift` — replace paged TabView with vertical `ScrollView` + `ScrollViewReader`, 12 month sections
- [x] 2.2 Build month section: month name header (`.title`, `.bold`, centered) + `LazyVGrid(columns: 7)` with weekday offset for day 1
- [x] 2.3 Build `DayCell` view — empty state: plain day number; today state: teal-colored number
- [x] 2.4 Build `DayCell` single photo state — circular thumbnail with white day number overlay + drop shadow, clipped to `Circle()`
- [x] 2.5 Build `DayCell` multi-photo collage — 2 photos: vertical split; 3 photos: left half + 2 stacked right; 4+: quad grid; all `.clipShape(Circle())`; 1pt gaps
- [x] 2.6 Add photo count badge — small teal circle with white count, bottom-trailing, shown when total photos > visible slots
- [x] 2.7 Add today accent ring for photo cells (teal border on circle)
- [x] 2.8 Auto-scroll to current month on appear via `ScrollViewReader.scrollTo("month-\(currentMonth)")`
- [x] 2.9 Build `DaySummarySheet` — `.sheet` with `[.medium, .large]` detents, date title + year entry cards
- [x] 2.10 Year entry card in sheet: year, weekday, location, 2-line text preview (serif), mini photo row, check-in stats
- [x] 2.11 "Add Entry" button in sheet when no current year entry — creates entry + navigates to `EntryDetailView`
- [x] 2.12 Wire tap on year card → dismiss sheet → navigate to `EntryDetailView` via `navigationDestination(for: EntryDestination.self)`
- [x] 2.13 Add tap scale feedback on day cells (0.95 → 1.0 spring animation)
- [x] 2.14 Remove or repurpose `TimelineView.swift` — `DaySummarySheet` replaces `DayTimelineView`; keep `YearCard` if reusable

## Phase 3: View/Write Mode Toggle (Feature C)

- [x] 3.1 Add `@State private var isViewMode = false` + toolbar button (`eye` / `square.and.pencil`) to `HomeView`
- [x] 3.2 Build `MarkdownTextView` — renders `diaryText` as `AttributedString(markdown:)` with serif font; inline markdown (bold, italic, strikethrough, code, links)
- [x] 3.3 Add list rendering — split by newlines, detect `- ` prefix, render with bullet characters
- [x] 3.4 In HomeView: when `isViewMode`, show `MarkdownTextView` instead of `TextEditor`; tap gesture → `isViewMode = false` + focus
- [x] 3.5 Add same `isViewMode` toggle + `MarkdownTextView` to `EntryDetailView`
- [x] 3.6 Crossfade animation between view/write modes (`.easeInOut(0.25)`)

## Phase 4: Polish & Verify

- [x] 4.1 Verify all views render correctly with new color palette (Home, Analytics, Settings, EntryDetail)
- [x] 4.2 Build succeeds — `xcodebuild build`
- [x] 4.3 All existing tests pass (69/69) — `xcodebuild test`
- [x] 4.4 Calendar grid layout correct across months (Jan weekday offset, Feb 28/29 days, etc.)

---

## Verification Commands
```bash
# Build
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
# Expected: BUILD SUCCEEDED

# Tests
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
# Expected: 69/69 tests pass
```

## Acceptance Criteria
1. Calendar tab shows 7-column grid with proper weekday alignment, scrollable through 12 months
2. Days with photos show circular thumbnails; multi-photo days show collage circles with count badge
3. Tapping a day opens compact summary sheet; tapping entry in sheet → EntryDetailView
4. Today highlighted with teal accent
5. Settings has Appearance section with System/Light/Dark picker
6. Dark mode uses #222831/#393E46/#00ADB5/#EEEEEE palette
7. Light mode is clean white with teal accent
8. Home and EntryDetailView have view/write toggle in toolbar
9. View mode renders markdown (bold, italic, lists)
10. Tapping rendered text switches to write mode
11. All existing tests pass
