import XCTest
@testable import ForeverDiary

final class VimEngineTests: XCTestCase {

    private var engine: VimEngine!

    override func setUp() {
        super.setUp()
        engine = VimEngine()
    }

    // MARK: - Initial State

    func testInitialModeIsNormal() {
        XCTAssertEqual(engine.currentMode, .normal)
    }

    func testInitialPendingCommandIsEmpty() {
        XCTAssertEqual(engine.pendingCommand, "")
    }

    func testInitialRegisterIsEmpty() {
        XCTAssertEqual(engine.register, "")
    }

    func testInitialSearchQueryIsEmpty() {
        XCTAssertEqual(engine.searchQuery, "")
    }

    func testInitialCountPrefixIsZero() {
        XCTAssertEqual(engine.countPrefix, 0)
    }

    // MARK: - Mode Transitions

    func testIEntersInsertMode() {
        let action = engine.processKey("i", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .changeMode(.insert) = action {} else {
            XCTFail("Expected changeMode(.insert), got \(action)")
        }
    }

    func testAEntersInsertMode() {
        let action = engine.processKey("a", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .changeMode(.insert) = action {} else {
            XCTFail("Expected changeMode(.insert), got \(action)")
        }
    }

    func testShiftAEntersInsertModeAtEndOfLine() {
        let action = engine.processKey("A", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .compositeAction(let actions) = action {
            XCTAssertTrue(actions.contains(where: {
                if case .changeMode(.insert) = $0 { return true }
                return false
            }))
        } else if case .changeMode(.insert) = action {
        } else {
            XCTFail("Expected insert mode entry, got \(action)")
        }
    }

    func testShiftIEntersInsertModeAtStartOfLine() {
        _ = engine.processKey("I", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
    }

    func testOEntersInsertModeWithNewLineBelow() {
        let action = engine.processKey("o", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .openLineBelow = action {} else {
            XCTFail("Expected openLineBelow, got \(action)")
        }
    }

    func testShiftOEntersInsertModeWithNewLineAbove() {
        let action = engine.processKey("O", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .openLineAbove = action {} else {
            XCTFail("Expected openLineAbove, got \(action)")
        }
    }

    func testEscapeFromInsertReturnsToNormal() {
        _ = engine.processKey("i", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)

        let action = engine.processKey("escape", modifiers: [])
        XCTAssertEqual(engine.currentMode, .normal)
        if case .changeMode(.normal) = action {} else {
            XCTFail("Expected changeMode(.normal), got \(action)")
        }
    }

    func testEscapeInNormalModeIsNoop() {
        let action = engine.processKey("escape", modifiers: [])
        XCTAssertEqual(engine.currentMode, .normal)
        if case .noop = action {} else {
            XCTFail("Expected noop, got \(action)")
        }
    }

    func testVEntersVisualMode() {
        let action = engine.processKey("v", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visual)
        if case .changeMode(.visual) = action {} else {
            XCTFail("Expected changeMode(.visual), got \(action)")
        }
    }

    func testShiftVEntersVisualLineMode() {
        let action = engine.processKey("V", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visualLine)
        if case .compositeAction(let actions) = action {
            XCTAssertTrue(actions.contains(where: {
                if case .changeMode(.visualLine) = $0 { return true }
                return false
            }))
            XCTAssertTrue(actions.contains(where: {
                if case .selectCurrentLine = $0 { return true }
                return false
            }))
        } else {
            XCTFail("Expected compositeAction with changeMode(.visualLine) + selectCurrentLine, got \(action)")
        }
    }

    func testEscapeFromVisualReturnsToNormal() {
        _ = engine.processKey("v", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visual)

        _ = engine.processKey("escape", modifiers: [])
        XCTAssertEqual(engine.currentMode, .normal)
    }

    // MARK: - Basic Motions

    func testHReturnsMoveLeft() {
        let action = engine.processKey("h", modifiers: [])
        if case .moveCursor(.left) = action {} else {
            XCTFail("Expected moveCursor(.left), got \(action)")
        }
    }

    func testJReturnsMoveDown() {
        let action = engine.processKey("j", modifiers: [])
        if case .moveCursor(.down) = action {} else {
            XCTFail("Expected moveCursor(.down), got \(action)")
        }
    }

    func testKReturnsMoveUp() {
        let action = engine.processKey("k", modifiers: [])
        if case .moveCursor(.up) = action {} else {
            XCTFail("Expected moveCursor(.up), got \(action)")
        }
    }

    func testLReturnsMoveRight() {
        let action = engine.processKey("l", modifiers: [])
        if case .moveCursor(.right) = action {} else {
            XCTFail("Expected moveCursor(.right), got \(action)")
        }
    }

    func testWReturnsMoveWordForward() {
        let action = engine.processKey("w", modifiers: [])
        if case .moveCursor(.wordForward) = action {} else {
            XCTFail("Expected moveCursor(.wordForward), got \(action)")
        }
    }

    func testBReturnsMoveWordBackward() {
        let action = engine.processKey("b", modifiers: [])
        if case .moveCursor(.wordBackward) = action {} else {
            XCTFail("Expected moveCursor(.wordBackward), got \(action)")
        }
    }

    func testEReturnsMoveWordEnd() {
        let action = engine.processKey("e", modifiers: [])
        if case .moveCursor(.wordEnd) = action {} else {
            XCTFail("Expected moveCursor(.wordEnd), got \(action)")
        }
    }

    func testZeroReturnsMoveLineStart() {
        let action = engine.processKey("0", modifiers: [])
        if case .moveCursor(.lineStart) = action {} else {
            XCTFail("Expected moveCursor(.lineStart), got \(action)")
        }
    }

    func testDollarReturnsMoveLineEnd() {
        let action = engine.processKey("$", modifiers: [])
        if case .moveCursor(.lineEnd) = action {} else {
            XCTFail("Expected moveCursor(.lineEnd), got \(action)")
        }
    }

    func testShiftGReturnsMoveDocumentEnd() {
        let action = engine.processKey("G", modifiers: [])
        if case .moveCursor(.documentEnd) = action {} else {
            XCTFail("Expected moveCursor(.documentEnd), got \(action)")
        }
    }

    func testGGReturnsMoveDocumentStart() {
        let action1 = engine.processKey("g", modifiers: [])
        if case .noop = action1 {} else {
            XCTFail("Expected noop for first g, got \(action1)")
        }
        XCTAssertEqual(engine.pendingCommand, "g")

        let action2 = engine.processKey("g", modifiers: [])
        if case .moveCursor(.documentStart) = action2 {} else {
            XCTFail("Expected moveCursor(.documentStart), got \(action2)")
        }
        XCTAssertEqual(engine.pendingCommand, "")
    }

    func testOpenBraceReturnsMoveParaUp() {
        let action = engine.processKey("{", modifiers: [])
        if case .moveCursor(.paragraphUp) = action {} else {
            XCTFail("Expected moveCursor(.paragraphUp), got \(action)")
        }
    }

    func testCloseBraceReturnsMoveParaDown() {
        let action = engine.processKey("}", modifiers: [])
        if case .moveCursor(.paragraphDown) = action {} else {
            XCTFail("Expected moveCursor(.paragraphDown), got \(action)")
        }
    }

    func testPercentReturnsMatchBracket() {
        let action = engine.processKey("%", modifiers: [])
        if case .moveCursor(.matchBracket) = action {} else {
            XCTFail("Expected moveCursor(.matchBracket), got \(action)")
        }
    }

    // MARK: - Single-Key Edits

    func testXReturnsDeleteChar() {
        let action = engine.processKey("x", modifiers: [])
        if case .deleteChar = action {} else {
            XCTFail("Expected deleteChar, got \(action)")
        }
    }

    func testPReturnsPutAfter() {
        let action = engine.processKey("p", modifiers: [])
        if case .putAfter = action {} else {
            XCTFail("Expected putAfter, got \(action)")
        }
    }

    func testShiftPReturnsPutBefore() {
        let action = engine.processKey("P", modifiers: [])
        if case .putBefore = action {} else {
            XCTFail("Expected putBefore, got \(action)")
        }
    }

    func testUReturnsUndo() {
        let action = engine.processKey("u", modifiers: [])
        if case .undo = action {} else {
            XCTFail("Expected undo, got \(action)")
        }
    }

    func testCtrlRReturnsRedo() {
        let action = engine.processKey("r", modifiers: .control)
        if case .redo = action {} else {
            XCTFail("Expected redo, got \(action)")
        }
    }

    // MARK: - Shortcuts (D, C, Y)

    func testShiftDReturnsDeleteToLineEnd() {
        let action = engine.processKey("D", modifiers: [])
        if case .deleteMotion(.lineEnd) = action {} else {
            XCTFail("Expected deleteMotion(.lineEnd), got \(action)")
        }
    }

    func testShiftCReturnsChangeToLineEnd() {
        let action = engine.processKey("C", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)
        if case .changeMotion(.lineEnd) = action {} else {
            XCTFail("Expected changeMotion(.lineEnd), got \(action)")
        }
    }

    func testShiftYReturnsYankLine() {
        let action = engine.processKey("Y", modifiers: [])
        if case .yankLine = action {} else {
            XCTFail("Expected yankLine, got \(action)")
        }
    }

    // MARK: - Line Operations

    func testShiftJReturnsJoinLines() {
        let action = engine.processKey("J", modifiers: [])
        if case .joinLines = action {} else {
            XCTFail("Expected joinLines, got \(action)")
        }
    }

    func testTildeReturnsToggleCase() {
        let action = engine.processKey("~", modifiers: [])
        if case .toggleCase = action {} else {
            XCTFail("Expected toggleCase, got \(action)")
        }
    }

    // MARK: - Indent/Outdent

    func testDoubleGreaterThanReturnsIndentLine() {
        _ = engine.processKey(">", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, ">")
        let action = engine.processKey(">", modifiers: [])
        if case .indentLine = action {} else {
            XCTFail("Expected indentLine, got \(action)")
        }
    }

    func testDoubleLessThanReturnsOutdentLine() {
        _ = engine.processKey("<", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "<")
        let action = engine.processKey("<", modifiers: [])
        if case .outdentLine = action {} else {
            XCTFail("Expected outdentLine, got \(action)")
        }
    }

    // MARK: - Replace Char

    func testRFollowedByCharReturnsReplaceChar() {
        _ = engine.processKey("r", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "r")
        let action = engine.processKey("x", modifiers: [])
        if case .replaceChar(let c) = action {
            XCTAssertEqual(c, Character("x"))
        } else {
            XCTFail("Expected replaceChar(x), got \(action)")
        }
    }

    // MARK: - Find/Till Char

    func testFFollowedByCharReturnsFindChar() {
        _ = engine.processKey("f", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "f")
        let action = engine.processKey("a", modifiers: [])
        if case .moveCursor(.findChar(let c, let forward)) = action {
            XCTAssertEqual(c, Character("a"))
            XCTAssertTrue(forward)
        } else {
            XCTFail("Expected moveCursor(.findChar(a, forward: true)), got \(action)")
        }
    }

    func testShiftFFollowedByCharReturnsFindCharBackward() {
        _ = engine.processKey("F", modifiers: [])
        let action = engine.processKey("z", modifiers: [])
        if case .moveCursor(.findChar(let c, let forward)) = action {
            XCTAssertEqual(c, Character("z"))
            XCTAssertFalse(forward)
        } else {
            XCTFail("Expected moveCursor(.findChar(z, forward: false)), got \(action)")
        }
    }

    func testTFollowedByCharReturnsTillChar() {
        _ = engine.processKey("t", modifiers: [])
        let action = engine.processKey("b", modifiers: [])
        if case .moveCursor(.tillChar(let c, let forward)) = action {
            XCTAssertEqual(c, Character("b"))
            XCTAssertTrue(forward)
        } else {
            XCTFail("Expected moveCursor(.tillChar(b, forward: true)), got \(action)")
        }
    }

    func testShiftTFollowedByCharReturnsTillCharBackward() {
        _ = engine.processKey("T", modifiers: [])
        let action = engine.processKey("c", modifiers: [])
        if case .moveCursor(.tillChar(let c, let forward)) = action {
            XCTAssertEqual(c, Character("c"))
            XCTAssertFalse(forward)
        } else {
            XCTFail("Expected moveCursor(.tillChar(c, forward: false)), got \(action)")
        }
    }

    // MARK: - Search Word Under Cursor

    func testStarReturnsSearchWordForward() {
        let action = engine.processKey("*", modifiers: [])
        if case .searchWordUnderCursor(let forward) = action {
            XCTAssertTrue(forward)
        } else {
            XCTFail("Expected searchWordUnderCursor(forward: true), got \(action)")
        }
    }

    func testHashReturnsSearchWordBackward() {
        let action = engine.processKey("#", modifiers: [])
        if case .searchWordUnderCursor(let forward) = action {
            XCTAssertFalse(forward)
        } else {
            XCTFail("Expected searchWordUnderCursor(forward: false), got \(action)")
        }
    }

    // MARK: - Operator + Motion Composition

    func testDDReturnsDeleteLine() {
        _ = engine.processKey("d", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "d")

        let action = engine.processKey("d", modifiers: [])
        if case .deleteLine = action {} else {
            XCTFail("Expected deleteLine, got \(action)")
        }
        XCTAssertEqual(engine.pendingCommand, "")
    }

    func testYYReturnsYankLine() {
        _ = engine.processKey("y", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "y")

        let action = engine.processKey("y", modifiers: [])
        if case .yankLine = action {} else {
            XCTFail("Expected yankLine, got \(action)")
        }
    }

    func testCCReturnsChangeLine() {
        _ = engine.processKey("c", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "c")

        let action = engine.processKey("c", modifiers: [])
        if case .changeLine = action {} else {
            XCTFail("Expected changeLine, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .insert)
    }

    func testDWReturnsDeleteWord() {
        _ = engine.processKey("d", modifiers: [])
        let action = engine.processKey("w", modifiers: [])
        if case .deleteMotion(.wordForward) = action {} else {
            XCTFail("Expected deleteMotion(.wordForward), got \(action)")
        }
    }

    func testCWReturnsChangeWord() {
        _ = engine.processKey("c", modifiers: [])
        let action = engine.processKey("w", modifiers: [])
        if case .changeMotion(.wordForward) = action {} else {
            XCTFail("Expected changeMotion(.wordForward), got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .insert)
    }

    func testDIWReturnsDeleteInnerWord() {
        _ = engine.processKey("d", modifiers: [])
        _ = engine.processKey("i", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "di")
        let action = engine.processKey("w", modifiers: [])
        if case .deleteInnerWord = action {} else {
            XCTFail("Expected deleteInnerWord, got \(action)")
        }
    }

    func testCIWReturnsChangeInnerWord() {
        _ = engine.processKey("c", modifiers: [])
        _ = engine.processKey("i", modifiers: [])
        let action = engine.processKey("w", modifiers: [])
        if case .changeInnerWord = action {} else {
            XCTFail("Expected changeInnerWord, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .insert)
    }

    func testYWReturnsYankWord() {
        _ = engine.processKey("y", modifiers: [])
        let action = engine.processKey("w", modifiers: [])
        if case .yankMotion(.wordForward) = action {} else {
            XCTFail("Expected yankMotion(.wordForward), got \(action)")
        }
    }

    func testDEReturnsDeleteWordEnd() {
        _ = engine.processKey("d", modifiers: [])
        let action = engine.processKey("e", modifiers: [])
        if case .deleteMotion(.wordEnd) = action {} else {
            XCTFail("Expected deleteMotion(.wordEnd), got \(action)")
        }
    }

    func testCEReturnsChangeWordEnd() {
        _ = engine.processKey("c", modifiers: [])
        let action = engine.processKey("e", modifiers: [])
        if case .changeMotion(.wordEnd) = action {} else {
            XCTFail("Expected changeMotion(.wordEnd), got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .insert)
    }

    // MARK: - Pending Command Cancellation

    func testEscapeCancelsPendingOperator() {
        _ = engine.processKey("d", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "d")

        let action = engine.processKey("escape", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "")
        if case .noop = action {} else {
            XCTFail("Expected noop after cancelling pending, got \(action)")
        }
    }

    func testInvalidMotionAfterOperatorCancelsPending() {
        _ = engine.processKey("d", modifiers: [])
        let action = engine.processKey("z", modifiers: [])
        XCTAssertEqual(engine.pendingCommand, "")
        if case .noop = action {} else {
            XCTFail("Expected noop for invalid motion, got \(action)")
        }
    }

    // MARK: - Search

    func testSlashEntersSearchMode() {
        let action = engine.processKey("/", modifiers: [])
        if case .enterSearch = action {} else {
            XCTFail("Expected enterSearch, got \(action)")
        }
    }

    func testNReturnsNextMatch() {
        let action = engine.processKey("n", modifiers: [])
        if case .nextMatch = action {} else {
            XCTFail("Expected nextMatch, got \(action)")
        }
    }

    func testShiftNReturnsPrevMatch() {
        let action = engine.processKey("N", modifiers: [])
        if case .prevMatch = action {} else {
            XCTFail("Expected prevMatch, got \(action)")
        }
    }

    // MARK: - Visual Mode Operations

    func testDInVisualModeReturnsDeleteSelection() {
        _ = engine.processKey("v", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visual)

        let action = engine.processKey("d", modifiers: [])
        if case .deleteSelection = action {} else {
            XCTFail("Expected deleteSelection, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .normal)
    }

    func testYInVisualModeReturnsYankSelection() {
        _ = engine.processKey("v", modifiers: [])
        let action = engine.processKey("y", modifiers: [])
        if case .yankSelection = action {} else {
            XCTFail("Expected yankSelection, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .normal)
    }

    func testCInVisualModeReturnsChangeSelection() {
        _ = engine.processKey("v", modifiers: [])
        let action = engine.processKey("c", modifiers: [])
        if case .changeSelection = action {} else {
            XCTFail("Expected changeSelection, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .insert)
    }

    func testIndentInVisualMode() {
        _ = engine.processKey("v", modifiers: [])
        let action = engine.processKey(">", modifiers: [])
        if case .indentLine = action {} else {
            XCTFail("Expected indentLine, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .normal)
    }

    func testOutdentInVisualMode() {
        _ = engine.processKey("v", modifiers: [])
        let action = engine.processKey("<", modifiers: [])
        if case .outdentLine = action {} else {
            XCTFail("Expected outdentLine, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .normal)
    }

    // MARK: - Insert Mode Passthrough

    func testKeysInInsertModeReturnInsertText() {
        _ = engine.processKey("i", modifiers: [])
        XCTAssertEqual(engine.currentMode, .insert)

        let action = engine.processKey("a", modifiers: [])
        if case .insertChar("a") = action {} else {
            XCTFail("Expected insertChar(a), got \(action)")
        }
    }

    // MARK: - VimMode Enum

    func testVimModeDisplayNames() {
        XCTAssertEqual(VimMode.normal.displayName, "NORMAL")
        XCTAssertEqual(VimMode.insert.displayName, "INSERT")
        XCTAssertEqual(VimMode.visual.displayName, "VISUAL")
        XCTAssertEqual(VimMode.visualLine.displayName, "VISUAL LINE")
    }

    // MARK: - Motions in Visual Mode

    func testMotionsWorkInVisualMode() {
        _ = engine.processKey("v", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visual)

        let action = engine.processKey("w", modifiers: [])
        if case .moveCursor(.wordForward) = action {} else {
            XCTFail("Expected moveCursor(.wordForward) in visual mode, got \(action)")
        }
        XCTAssertEqual(engine.currentMode, .visual)
    }

    // MARK: - Count Prefix

    func testCountPrefixWithMotion() {
        _ = engine.processKey("3", modifiers: [])
        XCTAssertEqual(engine.countPrefix, 3)

        let action = engine.processKey("j", modifiers: [])
        if case .compositeAction(let actions) = action {
            XCTAssertEqual(actions.count, 3)
            for a in actions {
                if case .moveCursor(.down) = a {} else {
                    XCTFail("Expected moveCursor(.down)")
                }
            }
        } else {
            XCTFail("Expected compositeAction with 3 moves, got \(action)")
        }
        XCTAssertEqual(engine.countPrefix, 0)
    }

    func testMultiDigitCountPrefix() {
        _ = engine.processKey("1", modifiers: [])
        _ = engine.processKey("2", modifiers: [])
        XCTAssertEqual(engine.countPrefix, 12)

        let action = engine.processKey("l", modifiers: [])
        if case .compositeAction(let actions) = action {
            XCTAssertEqual(actions.count, 12)
        } else {
            XCTFail("Expected compositeAction with 12 moves, got \(action)")
        }
    }

    func testZeroWithoutCountIsLineStart() {
        let action = engine.processKey("0", modifiers: [])
        if case .moveCursor(.lineStart) = action {} else {
            XCTFail("Expected moveCursor(.lineStart), got \(action)")
        }
    }

    func testZeroAfterDigitContinuesCount() {
        _ = engine.processKey("1", modifiers: [])
        _ = engine.processKey("0", modifiers: [])
        XCTAssertEqual(engine.countPrefix, 10)
    }

    func testEscapeResetsCountPrefix() {
        _ = engine.processKey("5", modifiers: [])
        XCTAssertEqual(engine.countPrefix, 5)
        _ = engine.processKey("escape", modifiers: [])
        XCTAssertEqual(engine.countPrefix, 0)
    }

    // MARK: - Dot Repeat

    func testDotReturnsRepeatLastChange() {
        let action = engine.processKey(".", modifiers: [])
        if case .repeatLastChange = action {} else {
            XCTFail("Expected repeatLastChange, got \(action)")
        }
    }

    func testLastEditRecordedForDeleteLine() {
        _ = engine.processKey("d", modifiers: [])
        _ = engine.processKey("d", modifiers: [])
        XCTAssertNotNil(engine.lastEdit)
        if case .deleteLine = engine.lastEdit?.action {} else {
            XCTFail("Expected lastEdit to be deleteLine")
        }
    }

    func testLastEditRecordedForReplaceChar() {
        _ = engine.processKey("r", modifiers: [])
        _ = engine.processKey("z", modifiers: [])
        XCTAssertNotNil(engine.lastEdit)
        if case .replaceChar(let c) = engine.lastEdit?.action {
            XCTAssertEqual(c, Character("z"))
        } else {
            XCTFail("Expected lastEdit to be replaceChar(z)")
        }
    }
}
