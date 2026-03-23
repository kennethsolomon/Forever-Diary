# Vim Mode + Zoom + Decimal Check-Ins

## Problem Statement

Three macOS app improvements:
1. **No vim keybindings** — power users want modal editing in the diary text editor
2. **No zoom controls** — can't scale text/UI size up or down
3. **Decimal input broken in check-ins** — can't type `5.5` for sleep hours because `format: .number` rejects the `.` character

## Key Decisions

### Feature 1: Full Vim Mode (Large)

1. **Wrap NSTextView** — SwiftUI `TextEditor` doesn't expose key events; replace with `NSViewRepresentable` wrapping `NSTextView`
2. **VimEngine state machine** — separate class handling Normal/Insert/Visual modes, command parsing
3. **Supported commands (initial set):**
   - **Modes:** Normal, Insert, Visual (line + char)
   - **Motion:** `h`, `j`, `k`, `l`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`, `{`, `}`
   - **Editing:** `i`, `a`, `o`, `O`, `A`, `I`, `x`, `dd`, `yy`, `p`, `P`, `cc`, `ciw`, `cw`, `diw`, `dw`, `u` (undo), `Ctrl+R` (redo)
   - **Search:** `/pattern`, `n`, `N`
   - **Visual:** `v`, `V`, `d`, `y` on selection
   - **Escape** returns to Normal mode
4. **Vim status bar** — shows mode (`-- NORMAL --`, `-- INSERT --`, `-- VISUAL --`) and pending command
5. **Toggle in Settings** — "Vim Mode" switch, off by default. When off, standard NSTextView behavior
6. **macOS only** — iOS keeps standard TextEditor (no hardware keyboard expectation)

### Feature 2: Zoom In/Out (Medium)

1. **AppStorage scale factor** — `fontScale: Double` stored in `@AppStorage("fontScale")`, default `1.0`
2. **Keyboard shortcuts** — `Cmd+=` (zoom in), `Cmd+-` (zoom out), `Cmd+0` (reset to 1.0)
3. **Settings slider** — continuous slider with presets: 75%, 100%, 125%, 150%
4. **Scale range** — 0.75x to 2.0x in 0.05 increments
5. **Environment-based** — custom `EnvironmentKey` so all views can read the scale
6. **Applies to both** — diary text editor font AND UI labels/headers scale proportionally
7. **macOS only** — iOS uses system Dynamic Type

### Feature 3: Decimal Check-Ins (Small)

1. **Root cause** — `format: .number` defaults to integer-like formatting, rejecting `.` during live editing
2. **Fix** — change to `format: .number.precision(.fractionLength(0...2))` allowing 0-2 decimal places
3. **Both platforms** — fix in `EntryDetailView.swift:274` (iOS) and `CheckInSectionView.swift:63` (macOS)
4. **No model changes** — `numberValue` is already `Double`
5. **No sync changes** — DynamoDB already stores numbers as floating point

## Chosen Approaches

| Feature | Approach | Files Affected |
|---------|----------|---------------|
| Vim mode | NSTextView wrapper + VimEngine + status bar + Settings toggle | New: `VimTextView.swift`, `VimEngine.swift`, `VimStatusBar.swift`. Modified: `EntryEditorView.swift`, `SettingsMacView.swift` |
| Zoom | AppStorage scale + Cmd shortcuts + Settings slider + environment key | New: `FontScaleEnvironment.swift`. Modified: `ForeverDiaryMacApp.swift`, `EntryEditorView.swift`, `SettingsMacView.swift`, `MainWindowView.swift`, other Mac views |
| Decimal check-ins | Change `.number` format precision | Modified: `EntryDetailView.swift`, `CheckInSectionView.swift` |

## Constraints (from lessons.md)

- No `@Attribute(.unique)` in SwiftData models
- Use `ModelContext(container)` in tests, not `container.mainContext`
- Guard test host init with `NSClassFromString("XCTestCase")` check

## Open Questions

- None — all decisions made
