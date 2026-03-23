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

    // Operator + motion
    case deleteMotion(CursorMotion)
    case changeMotion(CursorMotion)

    // Inner word
    case deleteInnerWord
    case changeInnerWord

    // Open line
    case openLineBelow
    case openLineAbove

    // Search
    case enterSearch
    case nextMatch
    case prevMatch

    // Visual mode
    case deleteSelection
    case yankSelection

    // Composite
    case compositeAction([VimAction])
}

// MARK: - Vim Engine

@Observable
final class VimEngine {
    var currentMode: VimMode = .normal
    var pendingCommand: String = ""
    var register: String = ""
    var searchQuery: String = ""

    func processKey(_ key: String, modifiers: ModifierFlags) -> VimAction {
        // Escape always cancels pending or returns to normal
        if key == "escape" {
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

    // MARK: - Normal Mode

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
        default: return nil
        }
    }

    private func processNormalMode(_ key: String, modifiers: ModifierFlags) -> VimAction {
        // Ctrl+R → redo
        if key == "r" && modifiers.contains(.control) {
            return .redo
        }

        // Handle pending operator
        if !pendingCommand.isEmpty {
            return processPendingCommand(key)
        }

        // Motions
        if let motion = motionForKey(key) {
            return motion
        }

        // Mode entry keys
        switch key {
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
            return .openLineBelow
        case "O":
            currentMode = .insert
            return .openLineAbove
        case "v":
            currentMode = .visual
            return .changeMode(.visual)
        case "V":
            currentMode = .visualLine
            return .changeMode(.visualLine)

        // Single-key edits
        case "x": return .deleteChar
        case "p": return .putAfter
        case "P": return .putBefore
        case "u": return .undo

        // Search
        case "/": return .enterSearch
        case "n": return .nextMatch
        case "N": return .prevMatch

        // Operators (wait for motion)
        case "d", "y", "c", "g":
            pendingCommand = key
            return .noop

        default:
            return .noop
        }
    }

    // MARK: - Pending Command

    private func processPendingCommand(_ key: String) -> VimAction {
        let full = pendingCommand + key

        switch full {
        // Double operators
        case "dd":
            pendingCommand = ""
            return .deleteLine
        case "yy":
            pendingCommand = ""
            return .yankLine
        case "cc":
            pendingCommand = ""
            currentMode = .insert
            return .changeLine
        case "gg":
            pendingCommand = ""
            return .moveCursor(.documentStart)

        // Operator + motion
        case "dw":
            pendingCommand = ""
            return .deleteMotion(.wordForward)
        case "db":
            pendingCommand = ""
            return .deleteMotion(.wordBackward)
        case "d$":
            pendingCommand = ""
            return .deleteMotion(.lineEnd)
        case "d0":
            pendingCommand = ""
            return .deleteMotion(.lineStart)
        case "cw":
            pendingCommand = ""
            currentMode = .insert
            return .changeMotion(.wordForward)
        case "cb":
            pendingCommand = ""
            currentMode = .insert
            return .changeMotion(.wordBackward)

        // Inner word (di, ci need another key)
        case "di", "ci":
            pendingCommand = full
            return .noop
        case "diw":
            pendingCommand = ""
            return .deleteInnerWord
        case "ciw":
            pendingCommand = ""
            currentMode = .insert
            return .changeInnerWord

        default:
            // Invalid sequence — cancel
            pendingCommand = ""
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
        default:
            return .noop
        }
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
