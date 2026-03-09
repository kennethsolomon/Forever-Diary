import SwiftUI
import SwiftData
import Charts

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [DiaryEntry]
    @Query(sort: \CheckInTemplate.sortOrder) private var templates: [CheckInTemplate]

    @State private var period: AnalyticsPeriod = .month

    var body: some View {
        NavigationStack {
            ScrollView {
                if allEntries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 16) {
                        periodPicker
                        streakCards
                        completionChart
                        habitCompletionSection
                    }
                    .padding(20)
                }
            }
            .background(Color("backgroundPrimary"))
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundStyle(Color("textSecondary").opacity(0.4))

            Text("Write more to see trends")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(Color("textSecondary"))

            Text("Analytics will appear once you start journaling.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color("textSecondary").opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(AnalyticsPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Streaks

    private var currentStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var checkDate = Date.now

        while true {
            let key = DiaryEntry.monthDayKey(from: checkDate)
            let year = DiaryEntry.year(from: checkDate)
            let hasEntry = allEntries.contains { $0.monthDayKey == key && $0.year == year }
            if hasEntry {
                streak += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }
        return streak
    }

    private var longestStreak: Int {
        let cal = Calendar.current
        let entryDates = Set(allEntries.map { cal.startOfDay(for: $0.date) })
        guard let earliest = entryDates.min(), let latest = entryDates.max() else { return 0 }

        var longest = 0
        var current = 0
        var checkDate = earliest

        while checkDate <= latest {
            if entryDates.contains(checkDate) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = next
        }
        return longest
    }

    private var streakCards: some View {
        HStack(spacing: 12) {
            StatCard(title: "Current Streak", value: "\(currentStreak)", unit: "days", icon: "flame.fill", color: Color("accentBright"))
            StatCard(title: "Longest Streak", value: "\(longestStreak)", unit: "days", icon: "trophy.fill", color: Color("habitComplete"))
        }
    }

    // MARK: - Completion Chart

    private var periodEntries: [DiaryEntry] {
        let cal = Calendar.current
        let now = Date.now
        let start: Date
        switch period {
        case .week:
            start = cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            start = cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:
            start = cal.date(byAdding: .year, value: -1, to: now) ?? now
        }
        return allEntries.filter { $0.date >= start }
    }

    private var periodDays: Int {
        switch period {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }

    private var completionRate: Double {
        guard periodDays > 0 else { return 0 }
        return min(1.0, Double(periodEntries.count) / Double(periodDays))
    }

    private var completionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entry Completion")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color("textPrimary"))

            HStack(spacing: 16) {
                Gauge(value: completionRate) {
                    Text("")
                } currentValueLabel: {
                    Text("\(Int(completionRate * 100))%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color("textPrimary"))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Color("accentBright"))
                .scaleEffect(1.5)
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(periodEntries.count) entries")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(Color("textPrimary"))
                    Text("out of \(periodDays) days")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Habit Completion

    private var habitCompletionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Habit Completion")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color("textPrimary"))

            if templates.isEmpty {
                Text("No habit templates configured.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            } else {
                ForEach(templates) { template in
                    let completed = periodEntries.filter { entry in
                        entry.safeCheckInValues.contains { value in
                            guard value.templateId == template.id else { return false }
                            if let b = value.boolValue { return b }
                            if let t = value.textValue { return !t.isEmpty }
                            if value.numberValue != nil { return true }
                            return false
                        }
                    }.count
                    let total = periodEntries.count
                    let rate = total > 0 ? Double(completed) / Double(total) : 0

                    HStack {
                        Text(template.label)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color("textPrimary"))
                            .frame(width: 90, alignment: .leading)

                        ProgressView(value: rate)
                            .tint(Color("habitComplete"))

                        Text("\(Int(rate * 100))%")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color("textSecondary"))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("textSecondary"))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color("textPrimary"))
                Text(unit)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}
