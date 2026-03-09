import Foundation
import SwiftData

@Model
final class DiaryEntry {
    var monthDayKey: String = ""
    var year: Int = 0
    var date: Date = Date.now
    var weekday: String = ""
    var diaryText: String = ""
    var locationText: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CheckInValue.entry)
    var checkInValues: [CheckInValue]? = []

    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.entry)
    var photoAssets: [PhotoAsset]? = []

    init(
        monthDayKey: String,
        year: Int,
        date: Date = .now,
        weekday: String,
        diaryText: String = "",
        locationText: String? = nil
    ) {
        self.monthDayKey = monthDayKey
        self.year = year
        self.date = date
        self.weekday = weekday
        self.diaryText = diaryText
        self.locationText = locationText
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Formatted month-day key from a Date (e.g. "03-09")
    static func monthDayKey(from date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return String(format: "%02d-%02d", month, day)
    }

    /// Weekday name from a Date (e.g. "Tuesday")
    static func weekdayName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// Year from a Date
    static func year(from date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }

    /// Safe accessor for check-in values (unwraps optional for CloudKit compat)
    var safeCheckInValues: [CheckInValue] {
        get { checkInValues ?? [] }
        set { checkInValues = newValue }
    }

    /// Safe accessor for photo assets (unwraps optional for CloudKit compat)
    var safePhotoAssets: [PhotoAsset] {
        get { photoAssets ?? [] }
        set { photoAssets = newValue }
    }

    /// Habit completion count
    var completedCheckIns: Int {
        safeCheckInValues.filter { value in
            if let b = value.boolValue { return b }
            if let t = value.textValue { return !t.isEmpty }
            if value.numberValue != nil { return true }
            return false
        }.count
    }
}
