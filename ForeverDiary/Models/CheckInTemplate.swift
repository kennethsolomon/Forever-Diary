import Foundation
import SwiftData

@Model
final class CheckInTemplate {
    var id: UUID = UUID()
    var label: String = ""
    var type: CheckInFieldType = CheckInFieldType.text
    var isActive: Bool = true
    var sortOrder: Int = 0

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
