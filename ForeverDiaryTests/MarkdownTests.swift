import XCTest
@testable import ForeverDiary

final class MarkdownTests: XCTestCase {

    // MARK: - Plain text

    func testPlainTextRemainsUnchanged() {
        let result = MarkdownTextView.parseMarkdown("Hello world")
        XCTAssertEqual(String(result.characters), "Hello world")
    }

    func testEmptyStringReturnsEmptyAttributedString() {
        let result = MarkdownTextView.parseMarkdown("")
        XCTAssertEqual(String(result.characters), "")
    }

    // MARK: - Bold

    func testBoldTextParsed() {
        let result = MarkdownTextView.parseMarkdown("This is **bold** text")
        let plain = String(result.characters)
        XCTAssertEqual(plain, "This is bold text")
    }

    // MARK: - Italic

    func testItalicTextParsed() {
        let result = MarkdownTextView.parseMarkdown("This is *italic* text")
        let plain = String(result.characters)
        XCTAssertEqual(plain, "This is italic text")
    }

    // MARK: - List conversion

    func testDashListConvertedToBullets() {
        let input = "- Item one\n- Item two\n- Item three"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("\u{2022} Item one"))
        XCTAssertTrue(plain.contains("\u{2022} Item two"))
        XCTAssertTrue(plain.contains("\u{2022} Item three"))
    }

    func testAsteriskListConvertedToBullets() {
        let input = "* First\n* Second"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("\u{2022} First"))
        XCTAssertTrue(plain.contains("\u{2022} Second"))
    }

    func testMixedListAndParagraph() {
        let input = "Intro\n- Item\nConclusion"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("Intro"))
        XCTAssertTrue(plain.contains("\u{2022} Item"))
        XCTAssertTrue(plain.contains("Conclusion"))
    }

    // MARK: - Multiline preservation

    func testMultipleLinesPreserved() {
        let input = "Line one\nLine two\nLine three"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("Line one"))
        XCTAssertTrue(plain.contains("Line two"))
        XCTAssertTrue(plain.contains("Line three"))
    }

    func testEmptyLinesPreserved() {
        let input = "First\n\nSecond"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertTrue(plain.contains("First"))
        XCTAssertTrue(plain.contains("Second"))
    }

    // MARK: - Edge cases

    func testDashWithoutSpaceNotConverted() {
        let input = "-not a list"
        let result = MarkdownTextView.parseMarkdown(input)
        let plain = String(result.characters)
        XCTAssertFalse(plain.contains("\u{2022}"))
    }

    func testStrikethroughParsed() {
        let result = MarkdownTextView.parseMarkdown("This is ~~deleted~~ text")
        let plain = String(result.characters)
        XCTAssertEqual(plain, "This is deleted text")
    }

    func testInlineCodeParsed() {
        let result = MarkdownTextView.parseMarkdown("Use `let x = 5` here")
        let plain = String(result.characters)
        XCTAssertEqual(plain, "Use let x = 5 here")
    }

    func testBoldAndItalicCombined() {
        let result = MarkdownTextView.parseMarkdown("This is ***bold italic*** text")
        let plain = String(result.characters)
        XCTAssertEqual(plain, "This is bold italic text")
    }
}
