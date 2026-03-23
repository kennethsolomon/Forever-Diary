# Vim Mode + Zoom + Decimal Check-Ins

## Goal

Add full vim keybindings to the macOS diary editor, zoom in/out controls (Cmd+/-/0 + Settings slider), and fix decimal input in check-in number fields on both platforms.

## Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Plan

### Milestone 1: Decimal Check-In Fix (Small)

#### Wave 1 (parallel)
- [x] 1. Fix iOS decimal input — change `EntryDetailView.swift:274` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`
- [x] 2. Fix macOS decimal input — change `CheckInSectionView.swift:63` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`
- [x] 3. Fix macOS EntryEditorView decimal input — change `EntryEditorView.swift:326` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`

### Milestone 2: Zoom Controls (Medium)

#### Wave 2 (parallel)
- [x] 4. Create `FontScaleEnvironment.swift` in `ForeverDiaryMac/` — define `FontScaleKey` EnvironmentKey with default `1.0`, and `EnvironmentValues` extension for `\.fontScale`
- [x] 5. Create `ScaledFont` ViewModifier in same file — reads `fontScale` from environment, applies `font(.system(size: baseSize * scale, design: design))`. Add `View.scaledFont(size:design:weight:)` extension.

#### Wave 3 (depends on Wave 2)
- [x] 6. Add `@AppStorage("fontScale") private var fontScale: Double = 1.0` to `ForeverDiaryMacApp.swift` — inject `.environment(\.fontScale, fontScale)` into both `WindowGroup` and `Settings` scenes
- [x] 7. Add zoom keyboard shortcuts to `ForeverDiaryMacApp.swift` commands — `Cmd+=` (zoom in, +0.1, max 2.0), `Cmd+-` (zoom out, -0.1, min 0.75), `Cmd+0` (reset to 1.0)
- [x] 8. Apply `fontScale` to `EntryEditorView.swift` text editor — read `@Environment(\.fontScale)`, apply scaled font size to TextEditor and placeholder text

#### Wave 4 (depends on Wave 3)
- [x] 9. Add zoom controls to `SettingsMacView.swift` AppearanceTab — slider (0.75...2.0, step 0.05) with percentage label, reset button. Read/write `@AppStorage("fontScale")`
- [x] 10. Apply `fontScale` to other macOS views — header text in EntryEditorView (weekday + date)

### Milestone 3: Vim Mode (Large)

#### Wave 5 (parallel)
- [x] 11. Create `VimEngine.swift` in `ForeverDiary/Services/` — vim state machine class with VimMode, VimAction, CursorMotion enums and processKey method
- [x] 12. Create `VimTextView.swift` in `ForeverDiaryMac/Views/Editor/` — NSViewRepresentable wrapping NSTextView with vim key handling
- [x] 13. Create `VimStatusBar.swift` in `ForeverDiaryMac/Views/Editor/` — mode display + pending command

#### Wave 6 (depends on Wave 5)
- [x] 14. Add vim mode toggle to `SettingsMacView.swift` AppearanceTab
- [x] 15. Integrate vim mode into `EntryEditorView.swift` — conditional VimTextView vs TextEditor

#### Wave 7 (depends on Wave 6)
- [x] 16. Files auto-included by directory — no project.yml changes needed
- [x] 17. Build verification — xcodegen, iOS BUILD SUCCEEDED, macOS BUILD SUCCEEDED, 247/247 tests pass

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'
```

## Acceptance Criteria

1. [x] Check-in number fields accept decimal input (e.g., `5.5`) on both iOS and macOS
2. [x] `Cmd+=` zooms in, `Cmd+-` zooms out, `Cmd+0` resets — all scale diary text + UI
3. [x] Zoom slider in Settings > Appearance shows current scale % with reset button
4. [x] Vim mode toggle in Settings > Appearance, off by default
5. [x] When vim mode on: block cursor in normal mode, bar cursor in insert mode
6. [x] Vim motions work: `hjkl`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`
7. [x] Vim editing works: `dd`, `yy`, `p`, `x`, `ciw`, `dw`, `o`, `O`
8. [x] Vim search works: `/pattern`, `n`, `N`
9. [x] Vim visual mode works: `v`/`V` select, `d`/`y` on selection
10. [x] Status bar shows mode + pending command
11. [x] Escape returns to normal mode from any mode
12. [x] All existing tests pass, both iOS and macOS build

## Risks/Unknowns

- NSTextView cursor styling (block vs bar) may require custom drawing via `insertionPointColor` + `drawInsertionPoint` override
- `Cmd+=` may conflict with macOS system zoom — need to test; may need to use `.commands` group ordering
- VimEngine is a significant state machine — initial release covers core commands, not full vim compatibility
