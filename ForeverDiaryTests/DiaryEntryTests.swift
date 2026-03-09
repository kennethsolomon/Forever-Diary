import XCTest
import SwiftData
@testable import ForeverDiary

final class DiaryEntryTests: XCTestCase {

    // MARK: - monthDayKey(from:)

    func testMonthDayKeyFormatsCorrectly() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.monthDayKey(from: date), "03-09")
    }

    func testMonthDayKeyPadsSingleDigits() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.monthDayKey(from: date), "01-05")
    }

    func testMonthDayKeyDoubleDigitMonth() {
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 25
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.monthDayKey(from: date), "12-25")
    }

    func testMonthDayKeyLeapDay() {
        var components = DateComponents()
        components.year = 2024
        components.month = 2
        components.day = 29
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.monthDayKey(from: date), "02-29")
    }

    // MARK: - weekdayName(from:)

    func testWeekdayNameReturnsFullName() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        let date = Calendar.current.date(from: components)!

        let weekday = DiaryEntry.weekdayName(from: date)
        // March 10, 2026 is a Tuesday
        XCTAssertEqual(weekday, "Tuesday")
    }

    func testWeekdayNameSunday() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.weekdayName(from: date), "Sunday")
    }

    // MARK: - year(from:)

    func testYearExtractsCorrectly() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.year(from: date), 2026)
    }

    func testYearForDifferentYear() {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(DiaryEntry.year(from: date), 2024)
    }

    // MARK: - Init

    func testInitSetsDefaults() {
        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")

        XCTAssertEqual(entry.monthDayKey, "03-10")
        XCTAssertEqual(entry.year, 2026)
        XCTAssertEqual(entry.weekday, "Tuesday")
        XCTAssertEqual(entry.diaryText, "")
        XCTAssertNil(entry.locationText)
        XCTAssertTrue(entry.safeCheckInValues.isEmpty)
        XCTAssertTrue(entry.safePhotoAssets.isEmpty)
    }

    func testInitWithAllParameters() {
        let entry = DiaryEntry(
            monthDayKey: "12-25",
            year: 2025,
            weekday: "Thursday",
            diaryText: "Christmas!",
            locationText: "Home"
        )

        XCTAssertEqual(entry.diaryText, "Christmas!")
        XCTAssertEqual(entry.locationText, "Home")
    }

    // MARK: - completedCheckIns

    func testCompletedCheckInsEmptyReturnsZero() {
        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        XCTAssertEqual(entry.completedCheckIns, 0)
    }

    func testCompletedCheckInsCountsMixedValues() {
        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")

        let boolTrue = CheckInValue(templateId: UUID(), boolValue: true)
        boolTrue.entry = entry
        let boolFalse = CheckInValue(templateId: UUID(), boolValue: false)
        boolFalse.entry = entry
        let textFilled = CheckInValue(templateId: UUID(), textValue: "Happy")
        textFilled.entry = entry
        let textEmpty = CheckInValue(templateId: UUID(), textValue: "")
        textEmpty.entry = entry
        let number = CheckInValue(templateId: UUID(), numberValue: 7.5)
        number.entry = entry

        entry.checkInValues = [boolTrue, boolFalse, textFilled, textEmpty, number]

        // boolTrue=yes, boolFalse=no, textFilled=yes, textEmpty=no, number=yes → 3
        XCTAssertEqual(entry.completedCheckIns, 3)
    }
}
