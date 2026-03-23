import SwiftUI
import AppKit

struct VimTextView: NSViewRepresentable {
    private static let baseFontSize: CGFloat = 17
    private static let serifFontName = "Georgia"

    @Binding var text: String
    var vimEngine: VimEngine
    var fontScale: Double

    private static func diaryFont(scale: Double) -> NSFont {
        let size = baseFontSize * scale
        return NSFont(name: serifFontName, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = VimNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true

        textView.font = Self.diaryFont(scale: fontScale)
        textView.textColor = NSColor(named: "textPrimary") ?? .textColor
        textView.insertionPointColor = NSColor(named: "accentBright") ?? .controlAccentColor
        textView.currentFontScale = fontScale

        textView.string = text
        textView.delegate = context.coordinator
        textView.vimEngine = vimEngine
        textView.coordinator = context.coordinator

        // Auto-resize
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.updateCursorStyle(textView: textView, mode: vimEngine.currentMode)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VimNSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        if textView.currentFontScale != fontScale {
            textView.font = Self.diaryFont(scale: fontScale)
            textView.currentFontScale = fontScale
        }

        context.coordinator.updateCursorStyle(textView: textView, mode: vimEngine.currentMode)
        textView.vimEngine = vimEngine
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VimTextView

        init(_ parent: VimTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func updateCursorStyle(textView: VimNSTextView, mode: VimMode) {
            textView.useBlockCursor = (mode == .normal || mode == .visual || mode == .visualLine)
            textView.needsDisplay = true
        }
    }
}

// MARK: - Custom NSTextView with Vim Key Handling

class VimNSTextView: NSTextView {
    var vimEngine: VimEngine?
    weak var coordinator: VimTextView.Coordinator?
    var useBlockCursor = false
    var currentFontScale: Double = 1.0

    override func keyDown(with event: NSEvent) {
        guard let engine = vimEngine else {
            super.keyDown(with: event)
            return
        }

        if engine.currentMode == .insert {
            if event.keyCode == 53 {
                let action = engine.processKey("escape", modifiers: [])
                handleAction(action)
                return
            }
            super.keyDown(with: event)
            return
        }

        let key = mapEventToKey(event)
        var modFlags: ModifierFlags = []
        if event.modifierFlags.contains(.control) { modFlags.insert(.control) }
        if event.modifierFlags.contains(.option) { modFlags.insert(.option) }
        if event.modifierFlags.contains(.command) { modFlags.insert(.command) }
        if event.modifierFlags.contains(.shift) { modFlags.insert(.shift) }

        let action = engine.processKey(key, modifiers: modFlags)
        handleAction(action)
    }

    private func mapEventToKey(_ event: NSEvent) -> String {
        if event.keyCode == 53 { return "escape" }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            if event.modifierFlags.contains(.shift), let shifted = event.characters, !shifted.isEmpty {
                return shifted
            }
            return chars
        }
        return ""
    }

    // MARK: - Action Handler

    private func handleAction(_ action: VimAction) {
        switch action {
        case .noop:
            break
        case .changeMode(let mode):
            coordinator?.updateCursorStyle(textView: self, mode: mode)
            if mode == .visualLine {
                selectLine()
            }
        case .moveCursor(let motion):
            let extending = vimEngine?.currentMode == .visual || vimEngine?.currentMode == .visualLine
            performMotion(motion, extendSelection: extending)
            if vimEngine?.currentMode == .visualLine {
                extendSelectionToFullLines()
            }
        case .deleteChar:
            deleteForward(nil)
        case .deleteLine:
            selectLine()
            let range = selectedRange()
            vimEngine?.register = (string as NSString).substring(with: range)
            delete(nil)
        case .yankLine:
            selectLine()
            let range = selectedRange()
            vimEngine?.register = (string as NSString).substring(with: range)
            setSelectedRange(NSRange(location: range.location, length: 0))
        case .changeLine:
            selectLineContent()
            delete(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .deleteMotion(let motion):
            let start = selectedRange().location
            performMotion(motion)
            let end = selectedRange().location
            let range = NSRange(location: min(start, end), length: abs(end - start))
            vimEngine?.register = (string as NSString).substring(with: range)
            setSelectedRange(range)
            delete(nil)
        case .changeMotion(let motion):
            let start = selectedRange().location
            performMotion(motion)
            let end = selectedRange().location
            let range = NSRange(location: min(start, end), length: abs(end - start))
            setSelectedRange(range)
            delete(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .yankMotion(let motion):
            let start = selectedRange().location
            performMotion(motion)
            let end = selectedRange().location
            let range = NSRange(location: min(start, end), length: abs(end - start))
            vimEngine?.register = (string as NSString).substring(with: range)
            setSelectedRange(NSRange(location: start, length: 0))
        case .deleteInnerWord:
            selectWord(nil)
            let range = selectedRange()
            vimEngine?.register = (string as NSString).substring(with: range)
            delete(nil)
        case .changeInnerWord:
            selectWord(nil)
            delete(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .putAfter:
            guard let reg = vimEngine?.register, !reg.isEmpty else { break }
            let loc = selectedRange().location
            let insertLoc = min(loc + 1, string.count)
            insertText(reg, replacementRange: NSRange(location: insertLoc, length: 0))
        case .putBefore:
            guard let reg = vimEngine?.register, !reg.isEmpty else { break }
            insertText(reg, replacementRange: NSRange(location: selectedRange().location, length: 0))
        case .undo:
            undoManager?.undo()
        case .redo:
            undoManager?.redo()
        case .openLineBelow:
            moveToEndOfLine(nil)
            insertNewline(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .openLineAbove:
            moveToBeginningOfLine(nil)
            insertNewline(nil)
            moveUp(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .joinLines:
            performJoinLines()
        case .indentLine:
            performIndent()
        case .outdentLine:
            performOutdent()
        case .replaceChar(let char):
            performReplaceChar(char)
        case .toggleCase:
            performToggleCase()
        case .enterSearch:
            performFindPanelAction(nil)
        case .nextMatch:
            performTextFinderAction(#selector(NSTextFinder.performAction(_:)))
        case .prevMatch:
            break
        case .searchWordUnderCursor(let forward):
            performSearchWordUnderCursor(forward: forward)
        case .deleteSelection:
            let range = selectedRange()
            vimEngine?.register = (string as NSString).substring(with: range)
            delete(nil)
        case .yankSelection:
            let range = selectedRange()
            vimEngine?.register = (string as NSString).substring(with: range)
            setSelectedRange(NSRange(location: range.location, length: 0))
        case .changeSelection:
            delete(nil)
            coordinator?.updateCursorStyle(textView: self, mode: .insert)
        case .selectCurrentLine:
            selectLine()
        case .repeatLastChange:
            performRepeatLastChange()
        case .insertChar:
            break
        case .compositeAction(let actions):
            for a in actions {
                handleAction(a)
            }
        }
    }

    // MARK: - Motions

    private func performMotion(_ motion: CursorMotion, extendSelection: Bool = false) {
        switch motion {
        case .findChar(let char, let forward):
            performFindChar(char, forward: forward, till: false, extendSelection: extendSelection)
            return
        case .tillChar(let char, let forward):
            performFindChar(char, forward: forward, till: true, extendSelection: extendSelection)
            return
        case .matchBracket:
            performMatchBracket(extendSelection: extendSelection)
            return
        default:
            break
        }

        if extendSelection {
            switch motion {
            case .left: moveLeftAndModifySelection(nil)
            case .right: moveRightAndModifySelection(nil)
            case .up: moveUpAndModifySelection(nil)
            case .down: moveDownAndModifySelection(nil)
            case .wordForward: moveWordForwardAndModifySelection(nil)
            case .wordBackward: moveWordBackwardAndModifySelection(nil)
            case .wordEnd: moveWordForwardAndModifySelection(nil)
            case .lineStart: moveToBeginningOfLineAndModifySelection(nil)
            case .lineEnd: moveToEndOfLineAndModifySelection(nil)
            case .documentStart: moveToBeginningOfDocumentAndModifySelection(nil)
            case .documentEnd: moveToEndOfDocumentAndModifySelection(nil)
            case .paragraphUp: moveToBeginningOfParagraphAndModifySelection(nil)
            case .paragraphDown: moveToEndOfParagraphAndModifySelection(nil)
            default: break
            }
        } else {
            switch motion {
            case .left: moveLeft(nil)
            case .right: moveRight(nil)
            case .up: moveUp(nil)
            case .down: moveDown(nil)
            case .wordForward: moveWordForward(nil)
            case .wordBackward: moveWordBackward(nil)
            case .wordEnd: moveWordForward(nil)
            case .lineStart: moveToBeginningOfLine(nil)
            case .lineEnd: moveToEndOfLine(nil)
            case .documentStart: moveToBeginningOfDocument(nil)
            case .documentEnd: moveToEndOfDocument(nil)
            case .paragraphUp: moveToBeginningOfParagraph(nil)
            case .paragraphDown: moveToEndOfParagraph(nil)
            default: break
            }
        }
    }

    // MARK: - Line Helpers

    private func selectLine() {
        moveToBeginningOfLine(nil)
        moveToEndOfLineAndModifySelection(nil)
        let range = selectedRange()
        if range.upperBound < string.count {
            setSelectedRange(NSRange(location: range.location, length: range.length + 1))
        }
    }

    private func selectLineContent() {
        moveToBeginningOfLine(nil)
        moveToEndOfLineAndModifySelection(nil)
    }

    private func extendSelectionToFullLines() {
        let range = selectedRange()
        let nsString = string as NSString
        let lineStart = nsString.lineRange(for: NSRange(location: range.location, length: 0)).location
        let endRange = nsString.lineRange(for: NSRange(location: NSMaxRange(range) > 0 ? NSMaxRange(range) - 1 : 0, length: 0))
        let lineEnd = NSMaxRange(endRange)
        setSelectedRange(NSRange(location: lineStart, length: lineEnd - lineStart))
    }

    // MARK: - New Operations

    private func performJoinLines() {
        moveToEndOfLine(nil)
        let loc = selectedRange().location
        guard loc < string.count else { return }
        // Delete newline + leading whitespace on next line
        let nsString = string as NSString
        var end = loc + 1
        while end < nsString.length {
            let c = nsString.character(at: end)
            if c != 0x20 && c != 0x09 { break } // space, tab
            end += 1
        }
        let range = NSRange(location: loc, length: end - loc)
        insertText(" ", replacementRange: range)
    }

    private func performIndent() {
        let range = selectedRange()
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: range)
        let lineText = nsString.substring(with: lineRange)
        let indented = "    " + lineText
        insertText(indented, replacementRange: lineRange)
    }

    private func performOutdent() {
        let range = selectedRange()
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: range)
        let lineText = nsString.substring(with: lineRange)
        var removed = lineText
        if removed.hasPrefix("    ") {
            removed = String(removed.dropFirst(4))
        } else if removed.hasPrefix("\t") {
            removed = String(removed.dropFirst(1))
        } else {
            // Remove leading spaces up to 4
            var count = 0
            while count < 4 && removed.first == " " {
                removed = String(removed.dropFirst(1))
                count += 1
            }
        }
        insertText(removed, replacementRange: lineRange)
    }

    private func performReplaceChar(_ char: Character) {
        let loc = selectedRange().location
        guard loc < string.count else { return }
        let range = NSRange(location: loc, length: 1)
        insertText(String(char), replacementRange: range)
        // Move cursor back to replaced position
        setSelectedRange(NSRange(location: loc, length: 0))
    }

    private func performToggleCase() {
        let range = selectedRange()
        let loc = range.length > 0 ? range : NSRange(location: range.location, length: 1)
        guard loc.location + loc.length <= string.count else { return }
        let original = (string as NSString).substring(with: loc)
        var toggled = ""
        for c in original {
            toggled += c.isUppercase ? c.lowercased() : c.uppercased()
        }
        insertText(toggled, replacementRange: loc)
        if range.length == 0 {
            // Single char — advance cursor
            setSelectedRange(NSRange(location: loc.location + 1, length: 0))
        }
    }

    private func performFindChar(_ char: Character, forward: Bool, till: Bool, extendSelection: Bool) {
        let loc = selectedRange().location
        let nsString = string as NSString
        let target = String(char)

        if forward {
            let searchStart = loc + 1
            guard searchStart < nsString.length else { return }
            let lineRange = nsString.lineRange(for: NSRange(location: loc, length: 0))
            let lineEnd = NSMaxRange(lineRange)
            let searchRange = NSRange(location: searchStart, length: lineEnd - searchStart)
            let found = nsString.range(of: target, range: searchRange)
            guard found.location != NSNotFound else { return }
            let dest = till ? found.location - 1 : found.location
            if extendSelection {
                let start = selectedRange().location
                setSelectedRange(NSRange(location: start, length: dest - start + 1))
            } else {
                setSelectedRange(NSRange(location: dest, length: 0))
            }
        } else {
            guard loc > 0 else { return }
            let lineRange = nsString.lineRange(for: NSRange(location: loc, length: 0))
            let lineStart = lineRange.location
            let searchRange = NSRange(location: lineStart, length: loc - lineStart)
            let found = nsString.range(of: target, options: .backwards, range: searchRange)
            guard found.location != NSNotFound else { return }
            let dest = till ? found.location + 1 : found.location
            if extendSelection {
                let end = NSMaxRange(selectedRange())
                setSelectedRange(NSRange(location: dest, length: end - dest))
            } else {
                setSelectedRange(NSRange(location: dest, length: 0))
            }
        }
    }

    private func performMatchBracket(extendSelection: Bool) {
        let loc = selectedRange().location
        guard loc < string.count else { return }
        let nsString = string as NSString
        let charAtCursor = nsString.character(at: loc)
        let pairs: [(UInt16, UInt16, Bool)] = [
            (0x28, 0x29, true),   // ( )
            (0x5B, 0x5D, true),   // [ ]
            (0x7B, 0x7D, true),   // { }
            (0x29, 0x28, false),  // ) (
            (0x5D, 0x5B, false),  // ] [
            (0x7D, 0x7B, false),  // } {
        ]
        guard let pair = pairs.first(where: { $0.0 == charAtCursor }) else { return }
        let match = pair.1
        let forward = pair.2
        var depth = 1
        var pos = loc

        if forward {
            pos += 1
            while pos < nsString.length && depth > 0 {
                let c = nsString.character(at: pos)
                if c == match { depth -= 1 }
                else if c == charAtCursor { depth += 1 }
                pos += 1
            }
            if depth == 0 {
                let dest = pos - 1
                if extendSelection {
                    setSelectedRange(NSRange(location: loc, length: dest - loc + 1))
                } else {
                    setSelectedRange(NSRange(location: dest, length: 0))
                }
            }
        } else {
            guard pos > 0 else { return }
            pos -= 1
            while pos >= 0 && depth > 0 {
                let c = nsString.character(at: pos)
                if c == match { depth -= 1 }
                else if c == charAtCursor { depth += 1 }
                if depth > 0 { pos -= 1 }
            }
            if depth == 0 {
                if extendSelection {
                    let end = NSMaxRange(selectedRange())
                    setSelectedRange(NSRange(location: pos, length: end - pos))
                } else {
                    setSelectedRange(NSRange(location: pos, length: 0))
                }
            }
        }
    }

    private func performSearchWordUnderCursor(forward: Bool) {
        selectWord(nil)
        let range = selectedRange()
        guard range.length > 0 else { return }
        let word = (string as NSString).substring(with: range)
        vimEngine?.searchQuery = word
        // Use NSTextView find
        setSelectedRange(NSRange(location: range.location, length: 0))
        let nsString = string as NSString
        let searchOptions: NSString.CompareOptions = forward ? [] : .backwards
        let searchRange: NSRange
        if forward {
            let start = NSMaxRange(range)
            searchRange = NSRange(location: start, length: nsString.length - start)
        } else {
            searchRange = NSRange(location: 0, length: range.location)
        }
        let found = nsString.range(of: word, options: searchOptions, range: searchRange)
        if found.location != NSNotFound {
            setSelectedRange(NSRange(location: found.location, length: 0))
            scrollRangeToVisible(found)
        }
    }

    private func performRepeatLastChange() {
        guard let last = vimEngine?.lastEdit else { return }
        for _ in 0..<max(1, last.count) {
            handleAction(last.action)
        }
    }

    // MARK: - Block Cursor Drawing

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if useBlockCursor {
            var blockRect = rect
            blockRect.size.width = max(8, rect.height * 0.6)
            color.withAlphaComponent(0.4).setFill()
            NSBezierPath(rect: blockRect).fill()
        } else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        }
    }

    override var rangeForUserCharacterAttributeChange: NSRange {
        if useBlockCursor {
            return selectedRange()
        }
        return super.rangeForUserCharacterAttributeChange
    }
}
