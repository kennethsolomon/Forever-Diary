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
            // Also acceptable
        } else {
            XCTFail("Expected insert mode entry, got \(action)")
        }
    }

    func testShiftIEntersInsertModeAtStartOfLine() {
        let action = engine.processKey("I", modifiers: [])
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
        if case .changeMode(.visualLine) = action {} else {
            XCTFail("Expected changeMode(.visualLine), got \(action)")
        }
    }

    func testEscapeFromVisualReturnsToNormal() {
        _ = engine.processKey("v", modifiers: [])
        XCTAssertEqual(engine.currentMode, .visual)

        let action = engine.processKey("escape", modifiers: [])
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

    // MARK: - Operator + Motion Composition

    func testDDReturnsDeleteLine() {
        let action1 = engine.processKey("d", modifiers: [])
        if case .noop = action1 {} else {
            XCTFail("Expected noop for first d, got \(action1)")
        }
        XCTAssertEqual(engine.pendingCommand, "d")

        let action2 = engine.processKey("d", modifiers: [])
        if case .deleteLine = action2 {} else {
            XCTFail("Expected deleteLine, got \(action2)")
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
        // Should stay in visual mode
        XCTAssertEqual(engine.currentMode, .visual)
    }
}
