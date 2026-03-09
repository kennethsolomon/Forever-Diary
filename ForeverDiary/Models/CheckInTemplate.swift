import Foundation
import SwiftData

@Model
final class CheckInTemplate {
    @Attribute(.unique) var id: UUID
    var label: String
    var type: CheckInFieldType
    var isActive: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        label: String,
        type: CheckInFieldType,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
