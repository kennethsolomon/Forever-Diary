import XCTest
import SwiftUI
@testable import ForeverDiary

final class ThemeTests: XCTestCase {

    // MARK: - AppTheme enum

    func testAppThemeSystemReturnsNilColorScheme() {
        XCTAssertNil(AppTheme.system.colorScheme)
    }

    func testAppThemeLightReturnsLightColorScheme() {
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
    }

    func testAppThemeDarkReturnsDarkColorScheme() {
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testAppThemeAllCasesContainsThreeCases() {
        XCTAssertEqual(AppTheme.allCases.count, 3)
    }

    func testAppThemeRawValues() {
        XCTAssertEqual(AppTheme.system.rawValue, "System")
        XCTAssertEqual(AppTheme.light.rawValue, "Light")
        XCTAssertEqual(AppTheme.dark.rawValue, "Dark")
    }

    func testAppThemeInitFromRawValue() {
        XCTAssertEqual(AppTheme(rawValue: "System"), .system)
        XCTAssertEqual(AppTheme(rawValue: "Light"), .light)
        XCTAssertEqual(AppTheme(rawValue: "Dark"), .dark)
    }

    func testAppThemeInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(AppTheme(rawValue: "Purple"))
        XCTAssertNil(AppTheme(rawValue: ""))
        XCTAssertNil(AppTheme(rawValue: "system"))  // case-sensitive
    }
}
