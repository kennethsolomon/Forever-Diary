import XCTest
import SwiftData
@testable import ForeverDiary

final class CalendarNavigationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    // MARK: - DayDestination

    func testDayDestinationEquality() {
        let a = DayDestination(monthDayKey: "03-10")
        let b = DayDestination(monthDayKey: "03-10")
        XCTAssertEqual(a, b)
    }

    func testDayDestinationInequality() {
        let a = DayDestination(monthDayKey: "03-10")
        let b = DayDestination(monthDayKey: "03-11")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - EntryDestination

    func testEntryDestinationEquality() {
        let a = EntryDestination(monthDayKey: "03-10", year: 2026)
        let b = EntryDestination(monthDayKey: "03-10", year: 2026)
        XCTAssertEqual(a, b)
    }

    func testEntryDestinationInequalityByKey() {
        let a = EntryDestination(monthDayKey: "03-10", year: 2026)
        let b = EntryDestination(monthDayKey: "03-11", year: 2026)
        XCTAssertNotEqual(a, b)
    }

    func testEntryDestinationInequalityByYear() {
        let a = EntryDestination(monthDayKey: "03-10", year: 2026)
        let b = EntryDestination(monthDayKey: "03-10", year: 2025)
        XCTAssertNotEqual(a, b)
    }

    func testEntryDestinationHashConsistency() {
        let dest = EntryDestination(monthDayKey: "12-25", year: 2024)
        let set: Set<EntryDestination> = [dest, dest]
        XCTAssertEqual(set.count, 1)
    }

    func testEntryDestinationHashUniqueness() {
        let a = EntryDestination(monthDayKey: "01-01", year: 2026)
        let b = EntryDestination(monthDayKey: "01-02", year: 2026)
        let set: Set<EntryDestination> = [a, b]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Eager Entry Creation (mirrors createAndNavigateToEntry logic)

    func testEagerEntryCreationFromMonthDayKey() throws {
        let context = try makeContext()

        let monthDayKey = "07-04"
        let year = 2026
        let parts = monthDayKey.split(separator: "-")
        var components = DateComponents()
        components.month = Int(parts[0])
        components.day = Int(parts[1])
        components.year = year
        let date = Calendar.current.date(from: components)!

        let entry = DiaryEntry(
            monthDayKey: monthDayKey,
            year: year,
            date: date,
            weekday: DiaryEntry.weekdayName(from: date)
        )
        context.insert(entry)
        try context.save()

        let key = "07-04"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.monthDayKey, "07-04")
        XCTAssertEqual(results.first?.year, 2026)
        XCTAssertEqual(results.first?.weekday, "Saturday")
        XCTAssertEqual(results.first?.diaryText, "")
    }

    func testQueryFindsExistingEntryBeforeInsert() throws {
        let context = try makeContext()

        let monthDayKey = "03-10"
        let year = 2026

        // Create first entry
        let entry1 = DiaryEntry(monthDayKey: monthDayKey, year: year, weekday: "Tuesday")
        context.insert(entry1)
        try context.save()

        // Simulate query-before-insert check (what loadEntry does)
        let key = "03-10"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let existing = try context.fetch(descriptor).first
        XCTAssertNotNil(existing, "Should find existing entry before creating duplicate")
    }

    // MARK: - Month Prefix Query (mirrors MonthPageView @Query)

    func testMonthPrefixQueryFiltersCorrectly() throws {
        let context = try makeContext()

        // March entries
        let mar1 = DiaryEntry(monthDayKey: "03-01", year: 2026, weekday: "Sunday")
        let mar15 = DiaryEntry(monthDayKey: "03-15", year: 2026, weekday: "Sunday")
        // April entry
        let apr1 = DiaryEntry(monthDayKey: "04-01", year: 2026, weekday: "Wednesday")

        context.insert(mar1)
        context.insert(mar15)
        context.insert(apr1)
        try context.save()

        let prefix = "03-"
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey.starts(with: prefix) }
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.monthDayKey.hasPrefix("03-") })
    }

    // MARK: - MonthDayKey Query with Year Sort (mirrors DayTimelineView @Query)

    func testMonthDayKeyQuerySortedByYearDescending() throws {
        let context = try makeContext()

        let entry2024 = DiaryEntry(monthDayKey: "03-10", year: 2024, weekday: "Sunday")
        let entry2026 = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        let entry2025 = DiaryEntry(monthDayKey: "03-10", year: 2025, weekday: "Monday")

        context.insert(entry2024)
        context.insert(entry2026)
        context.insert(entry2025)
        try context.save()

        let key = "03-10"
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key },
            sortBy: [SortDescriptor(\.year, order: .reverse)]
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].year, 2026)
        XCTAssertEqual(results[1].year, 2025)
        XCTAssertEqual(results[2].year, 2024)
    }
}
