import Foundation
import SwiftData

enum TemplateSeedService {
    static func seedDefaultTemplatesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<CheckInTemplate>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let defaults: [(String, CheckInFieldType, Int)] = [
            ("Mood", .text, 0),
            ("Gratitude", .text, 1),
            ("Weight", .number, 2),
            ("Exercise", .boolean, 3),
            ("Sleep", .number, 4),
        ]

        for (label, type, order) in defaults {
            let template = CheckInTemplate(label: label, type: type, sortOrder: order)
            context.insert(template)
        }
        try? context.save()
    }
}
