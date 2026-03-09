# TODO — 2026-03-10 — Forever Diary v1

## Goal
Build Forever Diary as an iPhone-first SwiftUI + SwiftData + CloudKit journaling app with a write-first home screen, yearless calendar browser, inline habits/photos, and analytics dashboard.

## Plan

### Phase 1: Project Scaffold & Assets
- [x] 1.1 Create Xcode project (ForeverDiary, SwiftUI lifecycle, iOS 17+, CloudKit entitlement)
- [x] 1.2 Create folder structure: App/, Models/, Views/{Home,Calendar,Analytics,Settings,Entry}/, Services/
- [x] 1.3 Create SVG logo (infinity + calendar concept, slate blue #4A6FA5)
- [x] 1.4 Add AppIcon to Assets.xcassets from logo
- [x] 1.5 Define color assets in asset catalog (backgroundPrimary, surfaceCard, textPrimary, textSecondary, accentSlate, accentBright, borderSubtle, habitComplete, destructive) with dark mode variants

### Phase 2: Data Models
- [x] 2.1 Create `CheckInFieldType` enum (boolean, text, number) with Codable conformance
- [x] 2.2 Create `DiaryEntry` @Model — query-before-insert for uniqueness (no #Unique with CloudKit)
- [x] 2.3 Create `CheckInTemplate` @Model
- [x] 2.4 Create `CheckInValue` @Model — links via templateId UUID
- [x] 2.5 Create `PhotoAsset` @Model — @Attribute(.externalStorage), max 10 photos, 10MB limit
- [x] 2.6 Configure ModelContainer with cloudKitDatabase: .automatic + template seed on first launch

### Phase 3: Tab Shell & Navigation
- [x] 3.1 Create root ContentView with TabView (iOS 17 .tabItem syntax)
- [x] 3.2 Create all views: HomeView, AnalyticsView, CalendarBrowserView, SettingsView
- [x] 3.3 Apply color theme: accentSlate tint

### Phase 4: Home Screen (Write-First)
- [x] 4.1 Date header with SF Pro Rounded
- [x] 4.2 TextEditor with serif font + placeholder
- [x] 4.3 Query/create DiaryEntry for today
- [x] 4.4 Auto-save with 1s debounce
- [x] 4.5 Compact action bar (location, photos, habits)
- [x] 4.6 Action bar taps (location sheet, photo picker, habit navigation)
- [x] 4.7 "Saved" indicator with fade
- [x] 4.8 @FocusState auto-focus

### Phase 5: Entry Detail (Shared, Scrollable)
- [x] 5.1 EntryDetailView with monthDayKey + year
- [x] 5.2 Scrollable layout: header → text → check-ins → photos
- [x] 5.3 Collapsible check-in section with spring animation
- [x] 5.4 Template inputs: Toggle, TextField, number field
- [x] 5.5 Create/update CheckInValue per template
- [x] 5.6 Photo grid: LazyVGrid 3 columns
- [x] 5.7 PhotosPicker with JPEG 0.7 compression + 300px thumbnails
- [x] 5.8 Full-screen photo preview
- [x] 5.9 Delete photo with context menu + confirmation
- [x] 5.10 Editable location field

### Phase 6: Calendar — Yearless Browser
- [x] 6.1 Horizontal month carousel (TabView .page)
- [x] 6.2 Month selector with chevron navigation
- [x] 6.3 Day list per month
- [x] 6.4 DayRow with dot indicators per year
- [x] 6.5 Today highlighted with star
- [x] 6.6 Tap DayRow → push TimelineView

### Phase 7: Timeline View
- [x] 7.1 TimelineView with entries sorted by year desc
- [x] 7.2 "Add Entry" button when current year missing
- [x] 7.3 YearCard with all required info
- [x] 7.4 Staggered fade-in animation
- [x] 7.5 Tap YearCard → push EntryDetailView
- [x] 7.6 Context menu delete with confirmation

### Phase 8: Settings
- [x] 8.1 Sections: Habit Templates, Sync, About
- [x] 8.2 Template list with sort, label, type, active badge
- [x] 8.3 Add template sheet
- [x] 8.4 Edit template sheet (pre-filled)
- [x] 8.5 Reorder with .onMove
- [x] 8.6 Delete with swipe + confirmation
- [x] 8.7 iCloud sync status (Automatic label)
- [x] 8.8 Version + build number

### Phase 9: Analytics
- [x] 9.1 Segment picker: Week / Month / Year
- [x] 9.2 Entry completion gauge
- [x] 9.3 Streak cards (current + longest)
- [x] 9.4 Habit completion % per template with progress bars
- [ ] 9.5 Trend chart: line chart of daily entry count over time (Swift Charts) — deferred, progress bars cover v1

### Phase 10: Location Service
- [x] 10.1 LocationService with @Observable + CLLocationManager
- [x] 10.2 Request when-in-use authorization
- [x] 10.3 Reverse geocode to city/area
- [x] 10.4 Graceful nil fallback
- [x] 10.5 NSLocationWhenInUseUsageDescription in Info.plist (via project.yml INFOPLIST_KEY)

### Phase 11: First Launch & Polish
- [x] 11.1 Seed 5 default templates via TemplateSeedService
- [x] 11.2 Empty states: Analytics placeholder, Calendar dots, Home placeholder text
- [x] 11.3 Photo permission: PhotosPicker handles this natively
- [ ] 11.4 Handle camera unavailable: hide camera option — deferred (PhotosPicker is library-only in v1)
- [x] 11.5 Dark mode: all 9 color assets have dark variants

## Verification
- `xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16' build` → BUILD SUCCEEDED
- Launch in Simulator → Home tab shows today's date, text editor focused
- Type text → "Saved" indicator appears, entry persisted (kill + relaunch verifies)
- Calendar → swipe months → tap day → timeline shows year cards
- Timeline → tap Add Entry → EntryDetailView opens for current year
- Settings → add/edit/reorder/delete templates → changes reflected in entry screens
- Analytics → shows completion data after creating a few entries
- Delete entry from timeline → confirmation → entry removed

## Acceptance Criteria
- [ ] App builds and runs on iOS 17+ Simulator without crashes
- [ ] Home screen: open app → start typing in < 1 tap
- [ ] Entries unique per (monthDayKey, year), no duplicates
- [ ] Calendar: swipe months, tap day, see timeline with year cards newest-first
- [ ] Habits: all 5 default templates render with correct input types
- [ ] Photos: add from library, view full-size, delete with confirmation
- [ ] Analytics: streak + completion data updates after adding entries
- [ ] Settings: full CRUD + reorder on habit templates
- [ ] Auto-save works (debounced, no data loss)
- [ ] SVG logo rendered as AppIcon
- [ ] Dark mode works across all screens
- [ ] Location auto-detect works, graceful fallback when denied

## Risks / Unknowns — All Handled Gracefully
- **SwiftData #Unique macro**: CloudKit does not support `#Unique` constraints. **Resolution:** Use query-before-insert as the primary uniqueness strategy — always fetch existing entry for (monthDayKey, year) before creating. Never rely on `#Unique` macro.
- **CloudKit + @Attribute(.externalStorage)**: CloudKit asset limit is 250MB per record. **Resolution:** Enforce max 10 photos per entry. Validate file size before save (reject > 10MB per photo after compression). Show user-facing alert if limit exceeded.
- **TextEditor keyboard avoidance**: SwiftUI TextEditor has inconsistent keyboard behavior in ScrollView. **Resolution:** Use `.scrollDismissesKeyboard(.interactively)` on all scrollable entry views. Add `.ignoresSafeArea(.keyboard)` where needed. Test on multiple device sizes.
- **New York font availability**: `.font(.serif)` should resolve to New York on iOS 17+. **Resolution:** Use `.font(.system(.body, design: .serif))` which is guaranteed on iOS 17. No external font dependency needed.

## Results
- (fill after execution)

## Errors
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |
