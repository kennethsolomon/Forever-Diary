import Foundation

enum CheckInFieldType: String, Codable, CaseIterable, Identifiable {
    case boolean
    case text
    case number

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .boolean: "Checkbox"
        case .text: "Text"
        case .number: "Number"
        }
    }
}
