import XCTest
import SwiftData
@testable import ForeverDiary

final class SyncModelTests: XCTestCase {

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

    // MARK: - DiaryEntry sync fields

    func testDiaryEntryDefaultSyncStatus() {
        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        XCTAssertEqual(entry.syncStatus, "pending")
        XCTAssertNil(entry.lastSyncedAt)
    }

    func testDiaryEntrySyncStatusCanBeUpdated() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)
        try context.save()

        entry.syncStatus = "synced"
        entry.lastSyncedAt = Date()
        try context.save()

        let key = "03-10"
        let yr = 2026
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        let fetched = try context.fetch(descriptor).first
        XCTAssertEqual(fetched?.syncStatus, "synced")
        XCTAssertNotNil(fetched?.lastSyncedAt)
    }

    func testQueryPendingEntries() throws {
        let context = try makeContext()

        let pending = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(pending)

        let synced = DiaryEntry(monthDayKey: "03-11", year: 2026, weekday: "Wednesday")
        synced.syncStatus = "synced"
        context.insert(synced)

        try context.save()

        let predicate = #Predicate<DiaryEntry> { $0.syncStatus == "pending" }
        let results = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: predicate))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.monthDayKey, "03-10")
    }

    // MARK: - CheckInTemplate sync fields

    func testCheckInTemplateDefaultSyncStatus() {
        let template = CheckInTemplate(label: "Mood", type: .text)
        XCTAssertEqual(template.syncStatus, "pending")
        XCTAssertNil(template.lastSyncedAt)
    }

    func testCheckInTemplateSyncStatusPersists() throws {
        let context = try makeContext()

        let template = CheckInTemplate(label: "Mood", type: .text)
        template.syncStatus = "synced"
        template.lastSyncedAt = Date()
        context.insert(template)
        try context.save()

        let results = try context.fetch(FetchDescriptor<CheckInTemplate>())
        XCTAssertEqual(results.first?.syncStatus, "synced")
        XCTAssertNotNil(results.first?.lastSyncedAt)
    }

    // MARK: - CheckInValue sync fields

    func testCheckInValueDefaultSyncStatus() {
        let value = CheckInValue(templateId: UUID(), boolValue: true)
        XCTAssertEqual(value.syncStatus, "pending")
        XCTAssertNil(value.lastSyncedAt)
    }

    // MARK: - PhotoAsset sync and S3 fields

    func testPhotoAssetDefaultSyncAndS3Fields() {
        let photo = PhotoAsset(imageData: Data([0x01]), thumbnailData: Data([0x02]))
        XCTAssertEqual(photo.syncStatus, "pending")
        XCTAssertNil(photo.lastSyncedAt)
        XCTAssertNil(photo.s3Key)
        XCTAssertNil(photo.s3ThumbKey)
    }

    func testPhotoAssetS3KeysPersist() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)

        let photo = PhotoAsset(imageData: Data([0x01]), thumbnailData: Data([0x02]))
        photo.entry = entry
        photo.s3Key = "photos/abc.jpg"
        photo.s3ThumbKey = "photos/abc_thumb.jpg"
        photo.syncStatus = "synced"
        context.insert(photo)
        try context.save()

        let results = try context.fetch(FetchDescriptor<PhotoAsset>())
        XCTAssertEqual(results.first?.s3Key, "photos/abc.jpg")
        XCTAssertEqual(results.first?.s3ThumbKey, "photos/abc_thumb.jpg")
        XCTAssertEqual(results.first?.syncStatus, "synced")
    }

    func testQueryPendingPhotos() throws {
        let context = try makeContext()

        let entry = DiaryEntry(monthDayKey: "03-10", year: 2026, weekday: "Tuesday")
        context.insert(entry)

        let pending = PhotoAsset(imageData: Data([0x01]), thumbnailData: Data([0x02]))
        pending.entry = entry
        context.insert(pending)

        let synced = PhotoAsset(imageData: Data([0x03]), thumbnailData: Data([0x04]))
        synced.entry = entry
        synced.syncStatus = "synced"
        synced.s3Key = "photos/done.jpg"
        context.insert(synced)

        try context.save()

        let predicate = #Predicate<PhotoAsset> { $0.syncStatus == "pending" }
        let results = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate))
        XCTAssertEqual(results.count, 1)
    }
}
