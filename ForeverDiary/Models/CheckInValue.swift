import Foundation
import SwiftData

@Model
final class CheckInValue {
    var id: UUID = UUID()
    var boolValue: Bool?
    var textValue: String?
    var numberValue: Double?
    var templateId: UUID = UUID()

    var updatedAt: Date = Date.now
    var syncStatus: String = "pending"
    var lastSyncedAt: Date?

    var entry: DiaryEntry?

    init(
        id: UUID = UUID(),
        templateId: UUID,
        boolValue: Bool? = nil,
        textValue: String? = nil,
        numberValue: Double? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.boolValue = boolValue
        self.textValue = textValue
        self.numberValue = numberValue
    }
}
