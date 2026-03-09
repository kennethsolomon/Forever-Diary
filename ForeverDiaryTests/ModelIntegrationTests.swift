import XCTest
import SwiftData
@testable import ForeverDiary

final class ModelIntegrationTests: XCTestCase {

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

    // MARK: - DiaryEntry CRUD

    func testCreateAndFetchEntry() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        entry.diaryText = "Test diary"
        context.insert(entry)
        try context.save()

        let key = "03-10"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.diaryText, "Test diary")
    }

    func testUpdateEntry() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)
        try context.save()

        entry.diaryText = "Updated"
        entry.locationText = "Manila"
        entry.updatedAt = .now
        try context.save()

        let key = "03-10"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.first?.diaryText, "Updated")
        XCTAssertEqual(results.first?.locationText, "Manila")
    }

    func testDeleteEntryCascadesCheckInValues() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)

        let value = CheckInValue(templateId: UUID(), boolValue: true)
        value.entry = entry
        context.insert(value)
        try context.save()

        XCTAssertEqual(entry.safeCheckInValues.count, 1)

        context.delete(entry)
        try context.save()

        let valueDescriptor = FetchDescriptor<CheckInValue>()
        let remainingValues = try context.fetch(valueDescriptor)
        XCTAssertEqual(remainingValues.count, 0)
    }

    func testDeleteEntryCascadesPhotos() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)

        let photo = PhotoAsset(imageData: Data([0x01]), thumbnailData: Data([0x02]))
        photo.entry = entry
        context.insert(photo)
        try context.save()

        XCTAssertEqual(entry.safePhotoAssets.count, 1)

        context.delete(entry)
        try context.save()

        let photoDescriptor = FetchDescriptor<PhotoAsset>()
        let remainingPhotos = try context.fetch(photoDescriptor)
        XCTAssertEqual(remainingPhotos.count, 0)
    }

    // MARK: - Query-Before-Insert Uniqueness

    func testQueryBeforeInsertPreventsduplicates() throws {
        let context = try makeContext()

        let entry1 = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        entry1.diaryText = "First"
        context.insert(entry1)
        try context.save()

        // Simulate query-before-insert pattern
        let key = "03-10"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let existing = try context.fetch(descriptor).first

        if let existing {
            // Update instead of creating duplicate
            existing.diaryText = "Updated"
            try context.save()
        }

        let allDescriptor = FetchDescriptor<DiaryEntry>()
        let all = try context.fetch(allDescriptor)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.diaryText, "Updated")
    }

    // MARK: - CheckInValue Linkage

    func testCheckInValueLinksToEntry() throws {
        let context = try makeContext()

        let templateId = UUID()
        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)

        let value = CheckInValue(templateId: templateId, textValue: "Happy")
        value.entry = entry
        context.insert(value)
        try context.save()

        XCTAssertEqual(entry.safeCheckInValues.count, 1)
        XCTAssertEqual(entry.safeCheckInValues.first?.textValue, "Happy")
        XCTAssertEqual(entry.safeCheckInValues.first?.templateId, templateId)
    }

    // MARK: - PhotoAsset Constants

    func testPhotoAssetMaxConstants() {
        XCTAssertEqual(PhotoAsset.maxPhotosPerEntry, 10)
        XCTAssertEqual(PhotoAsset.maxPhotoBytes, 10 * 1024 * 1024)
    }

    // MARK: - Multiple Years Same MonthDayKey

    func testMultipleYearsSameMonthDay() throws {
        let context = try makeContext()

        let entry2024 = DiaryEntry(monthDayKey: "03-10", year: 2024, weekday: "Sunday")
        entry2024.diaryText = "2024 entry"
        context.insert(entry2024)

        let entry2025 = DiaryEntry(monthDayKey: "03-10", year: 2025, weekday: "Monday")
        entry2025.diaryText = "2025 entry"
        context.insert(entry2025)

        let entry2026 = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        entry2026.diaryText = "2026 entry"
        context.insert(entry2026)
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
