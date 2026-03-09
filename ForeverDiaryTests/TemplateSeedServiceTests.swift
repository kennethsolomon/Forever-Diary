import XCTest
import SwiftData
@testable import ForeverDiary

final class TemplateSeedServiceTests: XCTestCase {

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

    // MARK: - Seeding

    func testSeedsDefaultTemplatesOnEmptyDB() throws {
        let context = try makeContext()

        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: context)

        let descriptor = FetchDescriptor<CheckInTemplate>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let templates = try context.fetch(descriptor)

        XCTAssertEqual(templates.count, 5)
        XCTAssertEqual(templates[0].label, "Mood")
        XCTAssertEqual(templates[0].type, .text)
        XCTAssertEqual(templates[1].label, "Gratitude")
        XCTAssertEqual(templates[1].type, .text)
        XCTAssertEqual(templates[2].label, "Weight")
        XCTAssertEqual(templates[2].type, .number)
        XCTAssertEqual(templates[3].label, "Exercise")
        XCTAssertEqual(templates[3].type, .boolean)
        XCTAssertEqual(templates[4].label, "Sleep")
        XCTAssertEqual(templates[4].type, .number)
    }

    func testDoesNotSeedWhenTemplatesExist() throws {
        let context = try makeContext()

        let existing = CheckInTemplate(label: "Custom", type: .text, sortOrder: 0)
        context.insert(existing)
        try context.save()

        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: context)

        let descriptor = FetchDescriptor<CheckInTemplate>()
        let count = try context.fetchCount(descriptor)

        XCTAssertEqual(count, 1)
    }

    func testSeededTemplatesAreAllActive() throws {
        let context = try makeContext()

        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: context)

        let descriptor = FetchDescriptor<CheckInTemplate>()
        let templates = try context.fetch(descriptor)

        for template in templates {
            XCTAssertTrue(template.isActive, "\(template.label) should be active")
        }
    }

    func testSeededTemplatesSortOrderIsSequential() throws {
        let context = try makeContext()

        TemplateSeedService.seedDefaultTemplatesIfNeeded(context: context)

        let descriptor = FetchDescriptor<CheckInTemplate>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let templates = try context.fetch(descriptor)

        for (index, template) in templates.enumerated() {
            XCTAssertEqual(template.sortOrder, index)
        }
    }
}
