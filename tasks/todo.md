# macOS App — Full iOS Feature Parity

## Goal
Rebuild the macOS `ForeverDiaryMac` app to full iOS feature parity in one pass: correct colors, rich "On This Day" entry list, full entry editor with photos + check-ins, real analytics, and complete settings with habit management.

## Lessons Applied
- No `@Attribute(.unique)` on any SwiftData model fields
- No CloudKit configuration in macOS target (uses local-only SwiftData)
- `PhotosPicker` from `PhotosUI` IS available on macOS 14+ (same API as iOS)
- macOS uses `NSImage` not `UIImage`; compress via `NSBitmapImageRep`
- `fullScreenCover` not available on macOS — use `.sheet` for photo gallery
- All colors: `Color("colorName")` from Assets, never raw `NSColor.*`
- `preferredColorScheme` applies at window root (WindowGroup body)

---

## Phase 1: Copy iOS Color Assets to macOS

- [ ] 1.1 Create `ForeverDiaryMac/Assets.xcassets/Colors/` directory structure with 10 colorsets matching iOS exactly:
  - `accentBright` (teal: R0 G173 B181, same light+dark)
  - `backgroundPrimary` (light: white; dark: R34 G40 B49)
  - `surfaceCard` (light: R245 G246 B248; dark: R57 G62 B70)
  - `textPrimary` (light: R34 G40 B49; dark: R238 G238 B238)
  - `textSecondary` (light: R107 G114 B128; dark: R158 G164 B171)
  - `habitComplete` (green: R107 G191 B138, same light+dark)
  - `destructive` (red: R232 G93 B93, same light+dark)
  - `accentSlate` (copy from iOS Assets)
  - `borderSubtle` (copy from iOS Assets)
- [ ] 1.2 Verify: `Color("backgroundPrimary")` resolves in macOS Simulator without error

---

## Phase 2: App Entry Point — Theme & Window Background

- [ ] 2.1 In `ForeverDiaryMacApp.swift`: add `@AppStorage("appTheme") var appTheme: String = AppTheme.system.rawValue` and apply `.preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme ?? nil)` to the WindowGroup root
- [ ] 2.2 Apply `.background(Color("backgroundPrimary"))` to `MainWindowView` root container

---

## Phase 3: Sidebar Color Fixes (CalendarSidebarView)

- [ ] 3.1 Replace all `NSColor.*` and hardcoded system color references in `CalendarSidebarView.swift` with `Color("name")` equivalents:
  - Selected day circle: `Color("accentBright")`
  - Today ring: `Color("accentBright").opacity(0.18)`
  - Day text selected: `.white`; today: `Color("accentBright")`; default: `Color("textPrimary")`
  - Entry dot: `Color("accentBright")`
  - Weekday abbreviations: `Color("textSecondary")`
  - Analytics button: `Color("textSecondary")`
- [ ] 3.2 Month header text (month name + year): `Color("textPrimary")` / `Color("textSecondary")`

---

## Phase 4: Column 2 — Rich "On This Day" Panel

Rewrite `DayEntryListView.swift` from a plain year list into iOS-style rich year cards.

- [ ] 4.1 Keep existing `@Query` for entries (filtered by `monthDayKey`, `deletedAt == nil`, sorted by year desc)
- [ ] 4.2 Replace each plain `entryRow()` with a `YearCard` subview containing:
  - **Header row**: Year (title3, semibold, `Color("textPrimary")`) + weekday (subheadline, `Color("textSecondary")`)
  - **Location** (if non-empty): mappin icon (size 10) + location text (caption, `Color("textSecondary")`)
  - **Text preview**: 2-line limit, serif font, `Color("textPrimary")`; or "No entry yet" in tertiary if empty
  - **Photo strip**: horizontal ScrollView, first 4 thumbnails as 60×60 rounded rectangles; "+N" indicator if more
  - **Bottom stats**: photo count label + check-in completion label (caption, `Color("textSecondary")`)
  - **Card container**: `Color("surfaceCard")` background, `cornerRadius: 12`, shadow `.black.opacity(0.04)`
- [ ] 4.3 Selected year card: accent-colored border `Color("accentBright")` at 1.5pt
- [ ] 4.4 "New Entry (year)" button: styled with `Color("accentBright")`, visible only when no current-year entry exists
- [ ] 4.5 Delete via right-click context menu (keep existing confirmation alert)
- [ ] 4.6 Fix year display: always use `String(entry.year)` (never integer interpolation which adds thousands separator)

---

## Phase 5: Column 3 — Full Entry Editor (match iOS EntryDetailView)

Rewrite `EntryEditorView.swift` to mirror iOS `EntryDetailView` structure.

- [ ] 5.1 **Header section**: weekday (title2, semibold, rounded) + formatted date + year; "Saved" transient indicator on right
- [ ] 5.2 **Location field**: `HStack` with mappin icon + `TextField("Add location", text: $locationText)` at top of scroll area (not in bottom bar); debounce 0.5s save
- [ ] 5.3 **Diary TextEditor**: serif font, min 250pt height, `scrollContentBackground(.hidden)`, `onChange` debounce 1s
- [ ] 5.4 **Photos section**:
  - `PhotosPicker` from `PhotosUI` (macOS 14+): `maxSelectionCount = max(0, 10 - currentPhotoCount)`, `matching: .images`
  - `LazyVGrid` 3 columns, `GridItem(.flexible(), spacing: 8)`
  - Each cell: thumbnail image, `aspectRatio(1, contentMode: .fill)`, `clipShape(RoundedRectangle(cornerRadius: 8))`
  - Right-click context menu on each photo: "Delete Photo" → confirmation alert → `syncService.deletePhoto()`
  - Tap photo → open `MacPhotoGalleryView` sheet
  - Add photo button: `+` icon shown only when < 10 photos
- [ ] 5.5 **macOS photo compression pipeline** (add `MacImageHelper.swift`):
  - Input: `PhotosPickerItem.loadTransferable(type: Data.self)` → `Data`
  - `NSImage(data:)` → resize to max 4096px (preserving aspect ratio) via `NSImage` draw into new size
  - Compress: `NSBitmapImageRep(data: tiffRepresentation)?.representation(using: .jpeg, properties: [.compressionFactor: 0.85])`
  - Thumbnail: resize to 300×300, compress at 0.8 quality
  - Create `PhotoAsset(imageData: compressed, thumbnailData: thumbData)`; set `entry` relation; `modelContext.insert`; save; schedule sync
- [ ] 5.6 **Check-in section** (expandable):
  - Chevron toggle with spring animation
  - `Color("surfaceCard")` background, cornerRadius 12, shadow
  - Toggles: `.tint(Color("habitComplete"))`
  - Text fields: `.textFieldStyle(.roundedBorder)`, maxWidth 180
  - Number fields: `.textFieldStyle(.roundedBorder)`, maxWidth 80
  - Completion count header: `completed/total`
- [ ] 5.7 **Action bar** (bottom strip): photo count + check-in progress only (location moved to top); styled with `Color("surfaceCard")` background + divider
- [ ] 5.8 Remove `CheckInSectionView.swift` — inline all check-in logic directly into `EntryEditorView`

---

## Phase 6: macOS Photo Gallery

Create `ForeverDiaryMac/Views/Components/MacPhotoGalleryView.swift`.

- [ ] 6.1 Sheet-based gallery (`.sheet` presentation, dark background)
- [ ] 6.2 `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` for swiping between photos
- [ ] 6.3 Each photo page: `Image(nsImage:).resizable().scaledToFit()`
- [ ] 6.4 Overlay controls:
  - Top-left: Close button (xmark, white circle `Color.white.opacity(0.15)`)
  - Top-right: counter "N / total"
  - Bottom: indicator dots (6pt circles; `Color("accentBright")` for current, `Color.white.opacity(0.3)` for others)
- [ ] 6.5 `MagnificationGesture` for pinch-zoom (1.0–4.0 range)
- [ ] 6.6 Double-tap resets zoom

---

## Phase 7: Analytics — Full Port

Rewrite `AnalyticsMacView.swift` as a full port of iOS `AnalyticsView`.

- [ ] 7.1 `@Query` all entries + active templates (same queries as iOS)
- [ ] 7.2 `AnalyticsPeriod` enum: Week / Month / Year (rawValue strings, CaseIterable)
- [ ] 7.3 **Computed properties** (identical logic to iOS):
  - `currentStreak: Int` — iterate backwards from today, count consecutive days with entries
  - `longestStreak: Int` — scan all entry dates oldest-to-newest, track max consecutive run
  - `periodEntries: [DiaryEntry]` — filter by date range (7 / 30 / 365 days)
  - `periodDays: Int` — 7, 30, or 365
  - `completionRate: Double` — `min(1.0, Double(periodEntries.count) / Double(periodDays))`
- [ ] 7.4 **StatCard** view: icon (SF Symbol) + value + unit + title; background `Color("surfaceCard")`, shadow
- [ ] 7.5 **Layout**:
  - Period picker (`.pickerStyle(.segmented)`)
  - 2-column HStack: current streak card + longest streak card
  - Completion gauge: `Gauge(value: completionRate)` with `.gaugeStyle(.accessoryCircular)`, scaled 1.5×
  - Habit completion: `ProgressView` per active template with label + %
- [ ] 7.6 Empty state: icon + "Start writing to see your analytics" text
- [ ] 7.7 Colors: `Color("backgroundPrimary")`, `Color("surfaceCard")`, `Color("accentBright")`, `Color("habitComplete")`, `Color("textPrimary")`, `Color("textSecondary")`
- [ ] 7.8 Open as `.sheet` from sidebar Analytics button; frame `minWidth: 500, minHeight: 400`

---

## Phase 8: Settings — Full 4-Tab Rewrite

Rewrite `SettingsMacView.swift` with Account / Appearance / Habits / Sync tabs.

- [ ] 8.1 **Account tab**: user icon + email (`cognitoAuth.userEmail`), "Sign Out" button (role: .destructive) with confirmation alert
- [ ] 8.2 **Appearance tab**: `Picker("Theme", selection: $appTheme)` with `AppTheme` cases, `.pickerStyle(.segmented)`; changes apply immediately via `preferredColorScheme`
- [ ] 8.3 **Habits tab** — full CRUD:
  - `@Query` templates sorted by `sortOrder`
  - `List` with `ForEach` + `.onMove(perform: reorderTemplates)` + `.onDelete(perform: deleteTemplate)`
  - Each row: label + type display + "Active" badge (`Color("habitComplete")` tint if active)
  - "Add Habit" toolbar button → sheet with `MacTemplateSheet`
  - Edit: click row → sheet with `MacTemplateSheet` pre-populated
  - `reorderTemplates`: update `sortOrder` sequentially, mark `.pending`, save, schedule sync
  - `deleteTemplate`: soft-delete via `syncService.deleteTemplate()` (check if this exists, otherwise hard-delete + mark pending)
- [ ] 8.4 **Sync tab**: `syncService.isSyncing` spinner + last sync time (`Text(lastSync, style: .relative)`) + error text (red) + "Sync Now" button (disabled while syncing)
- [ ] 8.5 Settings window frame: `minWidth: 520, minHeight: 380`
- [ ] 8.6 Delete `MacTemplateSheet.swift` and inline template editing into `SettingsMacView` OR keep sheet but ensure it has label + type + isActive toggle

---

## Phase 9: Sync on Entry Create

- [ ] 9.1 Verify `DayEntryListView.createEntry(year:)` calls `syncService.scheduleDebouncedSync()` after save (already added — confirm it's present)
- [ ] 9.2 Verify `EntryEditorView.ensureEntry()` is called inside `debounceSave` which already calls sync — no extra call needed

---

## Phase 10: Build Verification

- [ ] 10.1 `xcodegen generate` — output ends with `Generated: ForeverDiary.xcodeproj`
- [ ] 10.2 `xcodebuild -scheme ForeverDiaryMac -destination "generic/platform=macOS" build` → **BUILD SUCCEEDED**
- [ ] 10.3 `xcodebuild -scheme ForeverDiary -destination "platform=iOS Simulator,name=iPhone 16" build` → **BUILD SUCCEEDED** (iOS unchanged)

---

## Verification Commands

```bash
# After all phases:
cd /Users/kennethsolomon/Herd/forever-diary
xcodegen generate
xcodebuild -scheme ForeverDiaryMac -configuration Debug -destination "generic/platform=macOS" build 2>&1 | tail -5
xcodebuild -scheme ForeverDiary -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16" build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` for both.

---

## Acceptance Criteria

- [ ] macOS sidebar calendar uses `Color("accentBright")` for selection, custom colors throughout — no raw NSColor
- [ ] Column 2 shows rich year cards: text preview, photo thumbnails, check-in badge, location
- [ ] Column 3 entry editor has: diary text + location field + photo grid (3-col) + expandable check-ins
- [ ] Photos can be added via PhotosPicker (native macOS Photos picker); compressed pipeline runs
- [ ] Photo gallery opens as dark sheet with page-swipe, zoom, close button
- [ ] Analytics sheet shows real data: streaks, completion gauge, per-habit progress bars
- [ ] Settings has 4 tabs; Habits tab supports add / edit / reorder / delete with sync
- [ ] Appearance tab theme picker changes the window color scheme
- [ ] Both builds succeed with 0 errors

---

## Risks / Unknowns

- `PhotosPicker` on macOS 14 requires `PhotosUI` framework in the macOS target — confirm it's in `project.yml` frameworks list
- `NSBitmapImageRep` compression may differ from iOS `jpegData()` — test quality output
- `deleteTemplate` on `SyncService` — check if a soft-delete method exists for templates or needs implementing
- macOS `List` `.onMove` requires `.editMode` binding on macOS — may need `EditButton()` or manual edit state
