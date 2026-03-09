import XCTest
@testable import ForeverDiary

final class CheckInFieldTypeTests: XCTestCase {

    // MARK: - Codable

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in CheckInFieldType.allCases {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(CheckInFieldType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func testRawValues() {
        XCTAssertEqual(CheckInFieldType.boolean.rawValue, "boolean")
        XCTAssertEqual(CheckInFieldType.text.rawValue, "text")
        XCTAssertEqual(CheckInFieldType.number.rawValue, "number")
    }

    func testDecodesFromRawString() throws {
        let decoder = JSONDecoder()
        let data = "\"boolean\"".data(using: .utf8)!
        let decoded = try decoder.decode(CheckInFieldType.self, from: data)
        XCTAssertEqual(decoded, .boolean)
    }

    func testInvalidRawValueFails() {
        let decoder = JSONDecoder()
        let data = "\"invalid\"".data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(CheckInFieldType.self, from: data))
    }

    // MARK: - Display Name

    func testDisplayNames() {
        XCTAssertEqual(CheckInFieldType.boolean.displayName, "Checkbox")
        XCTAssertEqual(CheckInFieldType.text.displayName, "Text")
        XCTAssertEqual(CheckInFieldType.number.displayName, "Number")
    }

    // MARK: - Identifiable

    func testIdEqualsRawValue() {
        for type in CheckInFieldType.allCases {
            XCTAssertEqual(type.id, type.rawValue)
        }
    }

    // MARK: - CaseIterable

    func testAllCasesHasThreeEntries() {
        XCTAssertEqual(CheckInFieldType.allCases.count, 3)
    }
}
