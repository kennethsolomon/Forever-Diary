# Forever Diary — Calendar Navigation Freeze Bug

## Problem Statement
App freezes when tapping any day in the Calendar tab. Both new and existing entries cause an immediate freeze requiring app restart. The Home tab's navigation to EntryDetailView works fine.

## Key Decisions

### Root Cause: NavigationLink inside paged TabView inside NavigationStack
- `CalendarBrowserView.swift:10-18` wraps a `TabView(.page)` inside a `NavigationStack`
- `MonthPageView` (child of the paged TabView) uses `NavigationLink` for each day row
- The paged TabView's swipe gesture recognizers conflict with NavigationLink's tap gesture, causing the UI to freeze on tap
- This is a known SwiftUI issue — NavigationLink and paged TabView gesture recognizers are incompatible

### Evidence
- HomeView works fine — its NavigationStack has no paged TabView
- Freeze is immediate on tap — not triggered by any data operation
- Both new and existing entries freeze — navigation/gesture problem, not data
- TimelineView → EntryDetailView NavigationLinks may also be affected (nested 2 levels deep)

### Secondary Issue: Self-destructing NavigationLink for "Add Entry"
- `TimelineView.swift:40-58` wraps "Add Entry" NavigationLink in `if !hasCurrentYearEntry`
- When `ensureEntry()` saves a new entry, `@Query` re-evaluates, `hasCurrentYearEntry` becomes true
- The NavigationLink that pushed EntryDetailView is removed from the view hierarchy
- This would cause navigation instability after creating a new entry (separate from the freeze)

## Chosen Approach & Rationale
**Approach B (revised): Programmatic navigation + eager entry creation**

1. **MonthPageView**: Replace `NavigationLink` with `Button` + programmatic `navigationDestination(for:)` to avoid gesture conflict with paged TabView
2. **TimelineView**: Same pattern — `Button` + `navigationDestination(for:)` for consistency
3. **"Add Entry"**: Create the entry eagerly before navigating, so it appears in the ForEach list and uses a stable NavigationLink path

Rationale: Avoids the known SwiftUI gesture conflict entirely. Programmatic navigation via `@State` path is the recommended pattern for NavigationStack. Small complexity — mechanical replacement of NavigationLink with Button + navigationDestination.

## Files to Modify
- `ForeverDiary/Views/Calendar/CalendarBrowserView.swift` — add `@State` navigation path, add `.navigationDestination`, replace NavigationLinks in MonthPageView with Buttons
- `ForeverDiary/Views/Calendar/TimelineView.swift` — replace NavigationLinks with Buttons + navigationDestination, add eager entry creation for "Add Entry"

## Open Questions
- None — direction is locked in.
