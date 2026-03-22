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
- [ ] 1. Fix iOS decimal input — change `EntryDetailView.swift:274` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`
- [ ] 2. Fix macOS decimal input — change `CheckInSectionView.swift:63` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`
- [ ] 3. Fix macOS EntryEditorView decimal input — change `EntryEditorView.swift:326` from `format: .number` to `format: .number.precision(.fractionLength(0...2))`

### Milestone 2: Zoom Controls (Medium)

#### Wave 2 (parallel)
- [ ] 4. Create `FontScaleEnvironment.swift` in `ForeverDiaryMac/` — define `FontScaleKey` EnvironmentKey with default `1.0`, and `EnvironmentValues` extension for `\.fontScale`
- [ ] 5. Create `ScaledFont` ViewModifier in same file — reads `fontScale` from environment, applies `font(.system(size: baseSize * scale, design: design))`. Add `View.scaledFont(size:design:weight:)` extension.

#### Wave 3 (depends on Wave 2)
- [ ] 6. Add `@AppStorage("fontScale") private var fontScale: Double = 1.0` to `ForeverDiaryMacApp.swift` — inject `.environment(\.fontScale, fontScale)` into both `WindowGroup` and `Settings` scenes
- [ ] 7. Add zoom keyboard shortcuts to `ForeverDiaryMacApp.swift` commands — `Cmd+=` (zoom in, +0.1, max 2.0), `Cmd+-` (zoom out, -0.1, min 0.75), `Cmd+0` (reset to 1.0)
- [ ] 8. Apply `fontScale` to `EntryEditorView.swift` text editor — read `@Environment(\.fontScale)`, apply scaled font size to TextEditor and placeholder text

#### Wave 4 (depends on Wave 3)
- [ ] 9. Add zoom controls to `SettingsMacView.swift` AppearanceTab — slider (0.75...2.0, step 0.05) with percentage label, reset button. Read/write `@AppStorage("fontScale")`
- [ ] 10. Apply `fontScale` to other macOS views — `MainWindowView`, `CalendarSidebarView`, `EntryListView`, `DayEntryListView` headers/labels where appropriate

### Milestone 3: Vim Mode (Large)

#### Wave 5 (parallel)
- [ ] 11. Create `VimEngine.swift` in `ForeverDiaryMac/Views/Editor/` — vim state machine class:
  - `VimMode` enum: `.normal`, `.insert`, `.visual`, `.visualLine`
  - `currentMode` observable property
  - `pendingCommand` string for multi-key commands (e.g., `dd`, `gg`, `ci`)
  - `processKey(_ key: String, modifiers: NSEvent.ModifierFlags) -> VimAction` — returns action enum
  - `VimAction` enum: `.moveCursor(to:)`, `.insertText(String)`, `.deleteRange(NSRange)`, `.yankRange(NSRange)`, `.putText(String, before: Bool)`, `.changeMode(VimMode)`, `.undo`, `.redo`, `.search(String)`, `.nextMatch`, `.prevMatch`, `.noop`
  - Motions: `h`, `j`, `k`, `l`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`, `{`, `}`
  - Operators: `d` (delete), `y` (yank), `c` (change) with motion composition (`dw`, `dd`, `yy`, `cc`, `ciw`, `diw`, `cw`)
  - Mode entries: `i`, `a`, `o`, `O`, `A`, `I` → insert mode
  - Single-key edits: `x` (delete char), `p`/`P` (paste after/before)
  - `Escape` → normal mode
  - Search: `/` enters search input, `n`/`N` next/prev match
  - Visual: `v`/`V` enters visual/visual-line, `d`/`y` on selection
  - Internal register (clipboard) for yank/paste
- [ ] 12. Create `VimTextView.swift` in `ForeverDiaryMac/Views/Editor/` — `NSViewRepresentable` wrapping `NSTextView`:
  - `@Binding var text: String` for two-way binding
  - `@Binding var vimEngine: VimEngine` reference
  - `@Environment(\.fontScale) var fontScale` for scaled font
  - `Coordinator` as `NSTextViewDelegate` + key event handler
  - Override `keyDown(with:)` in coordinator — route to VimEngine when in normal/visual mode, pass through in insert mode
  - Update cursor style: block cursor in normal mode, bar cursor in insert mode
  - Handle `onChange` to update binding text
  - Support undo/redo via NSTextView's built-in undo manager
- [ ] 13. Create `VimStatusBar.swift` in `ForeverDiaryMac/Views/Editor/` — small bar below editor:
  - Shows current mode: `-- NORMAL --`, `-- INSERT --`, `-- VISUAL --`, `-- VISUAL LINE --`
  - Shows pending command (e.g., `d` waiting for motion)
  - Shows search query when in search mode
  - Color-coded: normal=default, insert=green, visual=orange

#### Wave 6 (depends on Wave 5)
- [ ] 14. Add vim mode toggle to `SettingsMacView.swift` AppearanceTab — `@AppStorage("vimMode") var vimMode: Bool = false`, Toggle switch with label "Vim Mode" and caption "Use vim keybindings in the diary editor"
- [ ] 15. Integrate vim mode into `EntryEditorView.swift` — read `@AppStorage("vimMode")`:
  - When vim mode ON: replace `TextEditor` with `VimTextView` + `VimStatusBar` below it
  - When vim mode OFF: keep current `TextEditor` behavior
  - `@StateObject var vimEngine = VimEngine()` for state management
  - Pass `diaryText` binding and `vimEngine` to `VimTextView`
  - Show `VimStatusBar` with mode + pending command from `vimEngine`

#### Wave 7 (depends on Wave 6)
- [ ] 16. Add `VimTextView`, `VimEngine`, `VimStatusBar`, `FontScaleEnvironment` to `project.yml` macOS sources (if not auto-included by directory)
- [ ] 17. Build verification — `xcodegen generate`, build iOS + macOS, run tests

## Verification Commands

```bash
xcodegen generate
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e' build
xcodebuild -scheme ForeverDiaryMac -destination 'platform=macOS' build
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 16e'
```

## Acceptance Criteria

1. [ ] Check-in number fields accept decimal input (e.g., `5.5`) on both iOS and macOS
2. [ ] `Cmd+=` zooms in, `Cmd+-` zooms out, `Cmd+0` resets — all scale diary text + UI
3. [ ] Zoom slider in Settings > Appearance shows current scale % with reset button
4. [ ] Vim mode toggle in Settings > Appearance, off by default
5. [ ] When vim mode on: block cursor in normal mode, bar cursor in insert mode
6. [ ] Vim motions work: `hjkl`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`
7. [ ] Vim editing works: `dd`, `yy`, `p`, `x`, `ciw`, `dw`, `o`, `O`
8. [ ] Vim search works: `/pattern`, `n`, `N`
9. [ ] Vim visual mode works: `v`/`V` select, `d`/`y` on selection
10. [ ] Status bar shows mode + pending command
11. [ ] Escape returns to normal mode from any mode
12. [ ] All existing tests pass, both iOS and macOS build

## Risks/Unknowns

- NSTextView cursor styling (block vs bar) may require custom drawing via `insertionPointColor` + `drawInsertionPoint` override
- `Cmd+=` may conflict with macOS system zoom — need to test; may need to use `.commands` group ordering
- VimEngine is a significant state machine — initial release covers core commands, not full vim compatibility
