import Foundation

// MARK: - Vim Mode

enum VimMode: Equatable {
    case normal
    case insert
    case visual
    case visualLine

    var displayName: String {
        switch self {
        case .normal: return "NORMAL"
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .visualLine: return "VISUAL LINE"
        }
    }
}

// MARK: - Cursor Motion

enum CursorMotion: Equatable {
    case left, right, up, down
    case wordForward, wordBackward, wordEnd
    case lineStart, lineEnd
    case documentStart, documentEnd
    case paragraphUp, paragraphDown
    case findChar(Character, forward: Bool)
    case tillChar(Character, forward: Bool)
    case matchBracket
}

// MARK: - Vim Action

enum VimAction: Equatable {
    case noop
    case moveCursor(CursorMotion)
    case changeMode(VimMode)
    case insertChar(String)

    // Single-key edits
    case deleteChar
    case putAfter
    case putBefore
    case undo
    case redo

    // Line operations
    case deleteLine
    case yankLine
    case changeLine
    case joinLines
    case indentLine
    case outdentLine

    // Operator + motion
    case deleteMotion(CursorMotion)
    case changeMotion(CursorMotion)
    case yankMotion(CursorMotion)

    // Inner word
    case deleteInnerWord
    case changeInnerWord

    // Open line
    case openLineBelow
    case openLineAbove

    // Character operations
    case replaceChar(Character)
    case toggleCase

    // Search
    case enterSearch
    case nextMatch
    case prevMatch
    case searchWordUnderCursor(forward: Bool)

    // Visual mode
    case deleteSelection
    case yankSelection
    case changeSelection
    case selectCurrentLine

    // Repeat
    case repeatLastChange

    // Composite
    case compositeAction([VimAction])
}

// MARK: - Recorded Edit (for dot repeat)

struct RecordedEdit: Equatable {
    let action: VimAction
    let count: Int
}

// MARK: - Vim Engine

@Observable
final class VimEngine {
    var currentMode: VimMode = .normal
    var pendingCommand: String = ""
    var register: String = ""
    var searchQuery: String = ""
    var countPrefix: Int = 0
    var lastEdit: RecordedEdit?

    func processKey(_ key: String, modifiers: ModifierFlags) -> VimAction {
        // Escape always cancels pending or returns to normal
        if key == "escape" {
            countPrefix = 0
            if !pendingCommand.isEmpty {
                pendingCommand = ""
                return .noop
            }
            if currentMode != .normal {
                currentMode = .normal
                return .changeMode(.normal)
            }
            return .noop
        }

        switch currentMode {
        case .insert:
            return processInsertMode(key, modifiers: modifiers)
        case .normal:
            return processNormalMode(key, modifiers: modifiers)
        case .visual, .visualLine:
            return processVisualMode(key, modifiers: modifiers)
        }
    }

    // MARK: - Insert Mode

    private func processInsertMode(_ key: String, modifiers: ModifierFlags) -> VimAction {
        return .insertChar(key)
    }

    // MARK: - Shared Motions

    private func motionForKey(_ key: String) -> VimAction? {
        switch key {
        case "h": return .moveCursor(.left)
        case "j": return .moveCursor(.down)
        case "k": return .moveCursor(.up)
        case "l": return .moveCursor(.right)
        case "w": return .moveCursor(.wordForward)
        case "b": return .moveCursor(.wordBackward)
        case "e": return .moveCursor(.wordEnd)
        case "0": return .moveCursor(.lineStart)
        case "$": return .moveCursor(.lineEnd)
        case "G": return .moveCursor(.documentEnd)
        case "{": return .moveCursor(.paragraphUp)
        case "}": return .moveCursor(.paragraphDown)
        case "%": return .moveCursor(.matchBracket)
        default: return nil
        }
    }

    // MARK: - Normal Mode

    private func processNormalMode(_ key: String, modifiers: ModifierFlags) -> VimAction {
        // Ctrl+R → redo
        if key == "r" && modifiers.contains(.control) {
            return .redo
        }

        // Handle pending operator
        if !pendingCommand.isEmpty {
            return processPendingCommand(key)
        }

        // Count prefix (digits 1-9 start, 0 only continues)
        if let digit = key.first, digit.isNumber {
            let d = Int(String(digit))!
            if d != 0 || countPrefix > 0 {
                countPrefix = countPrefix * 10 + d
                return .noop
            }
        }

        // Motions (with count)
        if let motion = motionForKey(key) {
            let action = applyCount(motion)
            countPrefix = 0
            return action
        }

        let result = processNormalCommand(key, modifiers: modifiers)
        countPrefix = 0
        return result
    }

    private func processNormalCommand(_ key: String, modifiers: ModifierFlags) -> VimAction {
        switch key {
        // Mode entry
        case "i":
            currentMode = .insert
            return .changeMode(.insert)
        case "a":
            currentMode = .insert
            return .changeMode(.insert)
        case "A":
            currentMode = .insert
            return .compositeAction([.moveCursor(.lineEnd), .changeMode(.insert)])
        case "I":
            currentMode = .insert
            return .compositeAction([.moveCursor(.lineStart), .changeMode(.insert)])
        case "o":
            currentMode = .insert
            let action = VimAction.openLineBelow
            lastEdit = RecordedEdit(action: action, count: 1)
            return action
        case "O":
            currentMode = .insert
            let action = VimAction.openLineAbove
            lastEdit = RecordedEdit(action: action, count: 1)
            return action
        case "v":
            currentMode = .visual
            return .changeMode(.visual)
        case "V":
            currentMode = .visualLine
            return .compositeAction([.changeMode(.visualLine), .selectCurrentLine])

        // Single-key edits
        case "x":
            let count = max(1, countPrefix)
            let action = VimAction.deleteChar
            lastEdit = RecordedEdit(action: action, count: count)
            return applyCount(action)
        case "p":
            return .putAfter
        case "P":
            return .putBefore
        case "u":
            return .undo

        // Shortcuts
        case "D":
            let action = VimAction.deleteMotion(.lineEnd)
            lastEdit = RecordedEdit(action: action, count: 1)
            return action
        case "C":
            currentMode = .insert
            let action = VimAction.changeMotion(.lineEnd)
            lastEdit = RecordedEdit(action: action, count: 1)
            return action
        case "Y":
            return .yankLine

        // Line operations
        case "J":
            let action = VimAction.joinLines
            lastEdit = RecordedEdit(action: action, count: 1)
            return action

        // Character operations
        case "~":
            let action = VimAction.toggleCase
            lastEdit = RecordedEdit(action: action, count: 1)
            return action

        // Search
        case "/": return .enterSearch
        case "n": return .nextMatch
        case "N": return .prevMatch
        case "*": return .searchWordUnderCursor(forward: true)
        case "#": return .searchWordUnderCursor(forward: false)

        // Repeat
        case ".":
            return .repeatLastChange

        // Operators (wait for motion)
        case "d", "y", "c", "g":
            pendingCommand = key
            return .noop

        // Find/till char (wait for next char)
        case "f", "F", "t", "T":
            pendingCommand = key
            return .noop

        // Replace char (wait for next char)
        case "r":
            pendingCommand = "r"
            return .noop

        // Indent/outdent (wait for second key)
        case ">", "<":
            pendingCommand = key
            return .noop

        default:
            return .noop
        }
    }

    // MARK: - Pending Command

    private func processPendingCommand(_ key: String) -> VimAction {
        let full = pendingCommand + key

        // Find/till char commands
        if pendingCommand.count == 1, let prefix = pendingCommand.first,
           "fFtT".contains(prefix), let char = key.first {
            pendingCommand = ""
            let forward = prefix == "f" || prefix == "t"
            let till = prefix == "t" || prefix == "T"
            let motion: CursorMotion = till
                ? .tillChar(char, forward: forward)
                : .findChar(char, forward: forward)
            let action = VimAction.moveCursor(motion)
            countPrefix = 0
            return action
        }

        // Replace char command
        if pendingCommand == "r", let char = key.first {
            pendingCommand = ""
            let action = VimAction.replaceChar(char)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        }

        // Indent/outdent
        if full == ">>" {
            pendingCommand = ""
            let action = VimAction.indentLine
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        }
        if full == "<<" {
            pendingCommand = ""
            let action = VimAction.outdentLine
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        }

        switch full {
        // Double operators
        case "dd":
            pendingCommand = ""
            let count = max(1, countPrefix)
            let action = VimAction.deleteLine
            lastEdit = RecordedEdit(action: action, count: count)
            countPrefix = 0
            return applyCount(action)
        case "yy":
            pendingCommand = ""
            countPrefix = 0
            return .yankLine
        case "cc":
            pendingCommand = ""
            currentMode = .insert
            let action = VimAction.changeLine
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "gg":
            pendingCommand = ""
            countPrefix = 0
            return .moveCursor(.documentStart)

        // Operator + motion
        case "dw":
            pendingCommand = ""
            let action = VimAction.deleteMotion(.wordForward)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "db":
            pendingCommand = ""
            let action = VimAction.deleteMotion(.wordBackward)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "de":
            pendingCommand = ""
            let action = VimAction.deleteMotion(.wordEnd)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "d$":
            pendingCommand = ""
            let action = VimAction.deleteMotion(.lineEnd)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "d0":
            pendingCommand = ""
            let action = VimAction.deleteMotion(.lineStart)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "cw":
            pendingCommand = ""
            currentMode = .insert
            let action = VimAction.changeMotion(.wordForward)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "cb":
            pendingCommand = ""
            currentMode = .insert
            let action = VimAction.changeMotion(.wordBackward)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "ce":
            pendingCommand = ""
            currentMode = .insert
            let action = VimAction.changeMotion(.wordEnd)
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "yw":
            pendingCommand = ""
            countPrefix = 0
            return .yankMotion(.wordForward)
        case "yb":
            pendingCommand = ""
            countPrefix = 0
            return .yankMotion(.wordBackward)
        case "y$":
            pendingCommand = ""
            countPrefix = 0
            return .yankMotion(.lineEnd)

        // Inner word (di, ci need another key)
        case "di", "ci", "yi":
            pendingCommand = full
            return .noop
        case "diw":
            pendingCommand = ""
            let action = VimAction.deleteInnerWord
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "ciw":
            pendingCommand = ""
            currentMode = .insert
            let action = VimAction.changeInnerWord
            lastEdit = RecordedEdit(action: action, count: 1)
            countPrefix = 0
            return action
        case "yiw":
            pendingCommand = ""
            countPrefix = 0
            return .yankMotion(.wordForward)

        default:
            // Invalid sequence — cancel
            pendingCommand = ""
            countPrefix = 0
            return .noop
        }
    }

    // MARK: - Visual Mode

    private func processVisualMode(_ key: String, modifiers: ModifierFlags) -> VimAction {
        // Motions extend selection
        if let motion = motionForKey(key) {
            return motion
        }

        switch key {
        case "d":
            currentMode = .normal
            return .deleteSelection
        case "y":
            currentMode = .normal
            return .yankSelection
        case "c":
            currentMode = .insert
            return .changeSelection
        case "J":
            currentMode = .normal
            return .joinLines
        case ">":
            currentMode = .normal
            return .indentLine
        case "<":
            currentMode = .normal
            return .outdentLine
        case "~":
            currentMode = .normal
            return .toggleCase
        case "U":
            currentMode = .normal
            return .toggleCase
        default:
            return .noop
        }
    }

    // MARK: - Count Prefix

    private func applyCount(_ action: VimAction) -> VimAction {
        let count = max(1, countPrefix)
        if count == 1 { return action }
        return .compositeAction(Array(repeating: action, count: count))
    }
}

// MARK: - Modifier Flags (cross-platform)

struct ModifierFlags: OptionSet {
    let rawValue: UInt

    static let control = ModifierFlags(rawValue: 1 << 0)
    static let option  = ModifierFlags(rawValue: 1 << 1)
    static let command = ModifierFlags(rawValue: 1 << 2)
    static let shift   = ModifierFlags(rawValue: 1 << 3)
}
