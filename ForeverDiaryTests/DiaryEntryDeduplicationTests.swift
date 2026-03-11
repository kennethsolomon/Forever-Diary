import XCTest
import SwiftData
@testable import ForeverDiary

/// Tests for deduplicated check-in logic added to DiaryEntry.
/// completedCheckIns now keeps the latest value per templateId (by updatedAt).
/// uniqueCheckInCount counts distinct templateIds.
final class DiaryEntryDeduplicationTests: XCTestCase {

    private var entry: DiaryEntry!

    override func setUp() {
        super.setUp()
        entry = DiaryEntry(monthDayKey: "03-11", year: 2026, weekday: "Wednesday")
    }

    // MARK: - uniqueCheckInCount

    func testUniqueCheckInCountEmptyReturnsZero() {
        XCTAssertEqual(entry.uniqueCheckInCount, 0)
    }

    func testUniqueCheckInCountDistinctTemplates() {
        let v1 = CheckInValue(templateId: UUID(), boolValue: true)
        let v2 = CheckInValue(templateId: UUID(), boolValue: false)
        let v3 = CheckInValue(templateId: UUID(), numberValue: 5)
        entry.checkInValues = [v1, v2, v3]
        XCTAssertEqual(entry.uniqueCheckInCount, 3)
    }

    func testUniqueCheckInCountDuplicateTemplateIdsCountOnce() {
        let sharedId = UUID()
        let v1 = CheckInValue(templateId: sharedId, boolValue: true)
        let v2 = CheckInValue(templateId: sharedId, boolValue: false)
        let v3 = CheckInValue(templateId: UUID(), boolValue: true)
        entry.checkInValues = [v1, v2, v3]
        // sharedId counted once + one unique = 2
        XCTAssertEqual(entry.uniqueCheckInCount, 2)
    }

    func testUniqueCheckInCountAllSameTemplateId() {
        let sharedId = UUID()
        let values = (0..<5).map { _ in CheckInValue(templateId: sharedId, boolValue: true) }
        entry.checkInValues = values
        XCTAssertEqual(entry.uniqueCheckInCount, 1)
    }

    // MARK: - completedCheckIns (deduplication)

    func testCompletedCheckInsNoDuplicates() {
        let v1 = CheckInValue(templateId: UUID(), boolValue: true)
        let v2 = CheckInValue(templateId: UUID(), boolValue: false)
        let v3 = CheckInValue(templateId: UUID(), textValue: "great")
        entry.checkInValues = [v1, v2, v3]
        // true + false + "great" → 2
        XCTAssertEqual(entry.completedCheckIns, 2)
    }

    func testCompletedCheckInsDeduplicatesKeepsLatestCompleted() {
        let templateId = UUID()
        let older = CheckInValue(templateId: templateId, boolValue: false)
        older.updatedAt = Date(timeIntervalSinceNow: -100)

        let newer = CheckInValue(templateId: templateId, boolValue: true)
        newer.updatedAt = Date(timeIntervalSinceNow: -10)

        entry.checkInValues = [older, newer]
        // Newer is true → counts as 1 completed
        XCTAssertEqual(entry.completedCheckIns, 1)
    }

    func testCompletedCheckInsDeduplicatesKeepsLatestNotCompleted() {
        let templateId = UUID()
        let older = CheckInValue(templateId: templateId, boolValue: true)
        older.updatedAt = Date(timeIntervalSinceNow: -100)

        let newer = CheckInValue(templateId: templateId, boolValue: false)
        newer.updatedAt = Date(timeIntervalSinceNow: -10)

        entry.checkInValues = [older, newer]
        // Newer is false → counts as 0 completed
        XCTAssertEqual(entry.completedCheckIns, 0)
    }

    func testCompletedCheckInsMultipleDuplicatesPicksMostRecent() {
        let templateId = UUID()
        var values: [CheckInValue] = []
        for i in 0..<5 {
            let v = CheckInValue(templateId: templateId, boolValue: i == 4)
            v.updatedAt = Date(timeIntervalSinceNow: Double(-100 + i * 10))
            values.append(v)
        }
        entry.checkInValues = values
        // Only the last one (i==4, boolValue=true, most recent) counts
        XCTAssertEqual(entry.completedCheckIns, 1)
    }

    func testCompletedCheckInsMixedTemplatesSomeDuplicated() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        // id1: duplicate — older=true, newer=false → not completed
        let id1old = CheckInValue(templateId: id1, boolValue: true)
        id1old.updatedAt = Date(timeIntervalSinceNow: -200)
        let id1new = CheckInValue(templateId: id1, boolValue: false)
        id1new.updatedAt = Date(timeIntervalSinceNow: -100)

        // id2: unique — completed
        let id2v = CheckInValue(templateId: id2, textValue: "ran 5k")
        id2v.updatedAt = Date(timeIntervalSinceNow: -50)

        // id3: unique — not completed
        let id3v = CheckInValue(templateId: id3, textValue: "")
        id3v.updatedAt = Date(timeIntervalSinceNow: -50)

        entry.checkInValues = [id1old, id1new, id2v, id3v]
        // id1 → false (0), id2 → "ran 5k" (1), id3 → "" (0) → total = 1
        XCTAssertEqual(entry.completedCheckIns, 1)
    }

    func testCompletedCheckInsNumberValueAlwaysCompleted() {
        let templateId = UUID()
        let older = CheckInValue(templateId: templateId, numberValue: 8)
        older.updatedAt = Date(timeIntervalSinceNow: -100)
        let newer = CheckInValue(templateId: templateId, numberValue: 0)
        newer.updatedAt = Date(timeIntervalSinceNow: -10)

        entry.checkInValues = [older, newer]
        // numberValue != nil → always completed regardless of value
        XCTAssertEqual(entry.completedCheckIns, 1)
    }

    // MARK: - CheckInTemplate new fields

    func testCheckInTemplateHasUpdatedAt() {
        let before = Date.now
        let template = CheckInTemplate(label: "Sleep", type: .boolean, isActive: true, sortOrder: 0)
        let after = Date.now
        XCTAssertGreaterThanOrEqual(template.updatedAt, before)
        XCTAssertLessThanOrEqual(template.updatedAt, after)
    }

    func testCheckInTemplateDeletedAtDefaultsToNil() {
        let template = CheckInTemplate(label: "Water", type: .number, isActive: true, sortOrder: 1)
        XCTAssertNil(template.deletedAt)
    }

    // MARK: - CheckInValue new field

    func testCheckInValueHasUpdatedAt() {
        let before = Date.now
        let value = CheckInValue(templateId: UUID(), boolValue: true)
        let after = Date.now
        XCTAssertGreaterThanOrEqual(value.updatedAt, before)
        XCTAssertLessThanOrEqual(value.updatedAt, after)
    }
}
