# Fix Calendar Navigation Freeze

## Goal
Fix the app freeze when tapping any day in the Calendar tab by replacing NavigationLink with programmatic navigation (Button + navigationDestination) to avoid gesture conflicts with the paged TabView.

## Lessons Applied
- No `@Attribute(.unique)` on any model fields
- Tests use `ModelContext(container)`, not `container.mainContext`
- Test host guard (`NSClassFromString("XCTestCase")`) skips network services

---

## Phase 1: CalendarBrowserView — Programmatic Navigation Path

- [x] 1.1 Add `@State private var navigationPath = NavigationPath()` to CalendarBrowserView
- [x] 1.2 Change `NavigationStack {` to `NavigationStack(path: $navigationPath) {`
- [x] 1.3 Define `EntryDestination` Hashable struct (monthDayKey: String, year: Int) — can live in CalendarBrowserView file
- [x] 1.4 Add `.navigationDestination(for: String.self) { key in DayTimelineView(...) }` for monthDayKey navigation
- [x] 1.5 Add `.navigationDestination(for: EntryDestination.self) { dest in EntryDetailView(...) }` for entry navigation
- [x] 1.6 In MonthPageView, accept `@Binding var navigationPath: NavigationPath`
- [x] 1.7 Replace MonthPageView's `NavigationLink` with `Button { navigationPath.append(key) }` styled like the current DayRow

## Phase 2: TimelineView — Programmatic Navigation + Eager Entry Creation

- [x] 2.1 In DayTimelineView (renamed from TimelineView to avoid SwiftUI conflict), accept `@Binding var navigationPath: NavigationPath`
- [x] 2.2 Replace ForEach `NavigationLink` with `Button { navigationPath.append(EntryDestination(...)) }`
- [x] 2.3 Replace "Add Entry" `NavigationLink` with `Button` that: creates entry via modelContext.insert + save, then appends `EntryDestination` to path
- [x] 2.4 Pass `navigationPath` binding from CalendarBrowserView → MonthPageView → DayTimelineView (through navigationDestination)

## Phase 3: Verify

- [x] 3.1 Build succeeds with zero errors
- [x] 3.2 All existing tests pass (58/58)
- [ ] 3.3 Manual: Calendar → tap day → TimelineView loads (no freeze)
- [ ] 3.4 Manual: tap existing entry → EntryDetailView loads (no freeze)
- [ ] 3.5 Manual: tap "Add Entry" → entry created, EntryDetailView loads (no freeze)
- [ ] 3.6 Manual: back navigation works at each level
- [ ] 3.7 Manual: Home tab navigation unaffected

---

## Verification Commands
```bash
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
# Expected: BUILD SUCCEEDED

xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
# Expected: all 58 tests pass
```

## Acceptance Criteria
1. Tapping any day in Calendar navigates to TimelineView without freezing
2. Tapping any entry in TimelineView navigates to EntryDetailView without freezing
3. "Add Entry" creates entry and navigates without freezing
4. Back navigation works at all levels
5. Home tab navigation unaffected
6. All 58 existing tests pass
7. Build succeeds with zero errors

## Risks/Unknowns
- None — straightforward NavigationLink → Button + navigationDestination replacement
