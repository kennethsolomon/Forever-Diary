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

        // Set cursor style based on mode
        context.coordinator.updateCursorStyle(textView: textView, mode: vimEngine.currentMode)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VimNSTextView else { return }

        // Update text if changed externally
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        // Update font only when scale changes
        if textView.currentFontScale != fontScale {
            textView.font = Self.diaryFont(scale: fontScale)
            textView.currentFontScale = fontScale
        }

        // Update cursor style
        context.coordinator.updateCursorStyle(textView: textView, mode: vimEngine.currentMode)

        textView.vimEngine = vimEngine
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

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

        // In insert mode, let most keys pass through to NSTextView
        if engine.currentMode == .insert {
            if event.keyCode == 53 { // Escape key
                let action = engine.processKey("escape", modifiers: [])
                handleAction(action)
                return
            }
            super.keyDown(with: event)
            return
        }

        // Normal/Visual mode — intercept all keys
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

        // Use characters for printable keys
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            // Handle shift variants via event.characters (uppercase)
            if event.modifierFlags.contains(.shift), let shifted = event.characters, !shifted.isEmpty {
                return shifted
            }
            return chars
        }
        return ""
    }

    private func handleAction(_ action: VimAction) {
        switch action {
        case .noop:
            break
        case .changeMode(let mode):
            coordinator?.updateCursorStyle(textView: self, mode: mode)
        case .moveCursor(let motion):
            performMotion(motion)
        case .deleteChar:
            deleteForward(nil)
        case .deleteLine:
            selectLine()
            let range = selectedRange()
            let selected = (string as NSString).substring(with: range)
            vimEngine?.register = selected
            delete(nil)
        case .yankLine:
            selectLine()
            let range = selectedRange()
            let selected = (string as NSString).substring(with: range)
            vimEngine?.register = selected
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
            let deleted = (string as NSString).substring(with: range)
            vimEngine?.register = deleted
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
        case .deleteInnerWord:
            selectWord(nil)
            let range = selectedRange()
            let deleted = (string as NSString).substring(with: range)
            vimEngine?.register = deleted
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
        case .enterSearch:
            performFindPanelAction(nil)
        case .nextMatch:
            // Use find panel next
            performTextFinderAction(#selector(NSTextFinder.performAction(_:)))
        case .prevMatch:
            break
        case .deleteSelection:
            let range = selectedRange()
            let deleted = (string as NSString).substring(with: range)
            vimEngine?.register = deleted
            delete(nil)
        case .yankSelection:
            let range = selectedRange()
            let yanked = (string as NSString).substring(with: range)
            vimEngine?.register = yanked
            setSelectedRange(NSRange(location: range.location, length: 0))
        case .insertChar:
            break // Should not reach here in normal mode
        case .compositeAction(let actions):
            for a in actions {
                handleAction(a)
            }
        }
    }

    private func performMotion(_ motion: CursorMotion) {
        switch motion {
        case .left: moveLeft(nil)
        case .right: moveRight(nil)
        case .up: moveUp(nil)
        case .down: moveDown(nil)
        case .wordForward: moveWordForward(nil)
        case .wordBackward: moveWordBackward(nil)
        case .wordEnd: moveWordForward(nil) // Approximate
        case .lineStart: moveToBeginningOfLine(nil)
        case .lineEnd: moveToEndOfLine(nil)
        case .documentStart: moveToBeginningOfDocument(nil)
        case .documentEnd: moveToEndOfDocument(nil)
        case .paragraphUp: moveToBeginningOfParagraph(nil)
        case .paragraphDown: moveToEndOfParagraph(nil)
        }
    }

    private func selectLine() {
        moveToBeginningOfLine(nil)
        moveToEndOfLineAndModifySelection(nil)
        // Include newline if present
        let range = selectedRange()
        if range.upperBound < string.count {
            setSelectedRange(NSRange(location: range.location, length: range.length + 1))
        }
    }

    private func selectLineContent() {
        moveToBeginningOfLine(nil)
        moveToEndOfLineAndModifySelection(nil)
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
