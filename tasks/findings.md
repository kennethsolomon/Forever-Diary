# Forever Diary — macOS Full iOS Parity Rebuild

## Problem Statement
The macOS app was ~40% feature-complete. Missing: real analytics, photos, custom color palette, rich "On This Day" entry panel, full settings with habit CRUD, and photo gallery. The user wants full iOS feature parity adapted for a 3-column Mac desktop layout.

## Key Decisions

1. **Same 10 iOS colorsets** copied verbatim into `ForeverDiaryMac/Assets.xcassets/Colors/` — all views use `Color("name")`, no raw `NSColor.*`
2. **3-column layout confirmed**:
   - Column 1 (~170px): Compact month mini-calendar sidebar
   - Column 2 (~300px): Rich "On This Day" year cards (text preview + photo thumbnails + check-in badge + location)
   - Column 3 (remaining): Full entry editor — diary text + location + photos + check-ins
3. **Photos**: `PhotosPicker` from `PhotosUI` (macOS 14+, same API as iOS) with `NSImage`-based compression pipeline (NSBitmapImageRep JPEG). Max 10 photos, 4096px resize, 0.85 quality, 300px thumbnail.
4. **Photo gallery**: Dark `.sheet` presentation with `TabView(.page)`, pinch-zoom, X close button (no drag-to-dismiss on macOS).
5. **Analytics**: Full port of iOS `AnalyticsView` — period picker, streak cards, completion gauge, per-habit progress bars. Opens as `.sheet` from sidebar Analytics button.
6. **Settings**: 4-tab macOS settings window (⌘,): Account | Appearance | Habits | Sync. Habits tab has full CRUD with drag-to-reorder, delete, and edit sheet.
7. **One pass**: All features implemented together, not incrementally.

## Chosen Approach
Port iOS features 1:1 adapted for Mac 3-column split view. Rewrite all macOS views; no iOS files touched.

## Constraints (from lessons.md)
- No `@Attribute(.unique)` on SwiftData models
- macOS target uses local-only SwiftData (no CloudKit)
- All colors via `Color("name")` asset catalog
- `preferredColorScheme` applied at WindowGroup root from AppStorage

## Open Questions
- Confirm `PhotosUI` framework is added to macOS target in `project.yml`
- Confirm `SyncService.deleteTemplate()` soft-delete exists or needs adding
