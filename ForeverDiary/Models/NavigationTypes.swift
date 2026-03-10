import Foundation

struct EntryDestination: Hashable {
    let monthDayKey: String
    let year: Int
}

struct DaySheetItem: Identifiable {
    let id: String
    var monthDayKey: String { id }
}
