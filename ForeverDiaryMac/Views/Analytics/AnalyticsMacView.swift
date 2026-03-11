import SwiftUI
import SwiftData
import Charts

struct AnalyticsMacView: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var allEntries: [DiaryEntry]
    @Query private var templates: [CheckInTemplate]

    @State private var period: AnalyticsPeriod = .month

    init() {
        let sortOrder = SortDescriptor<CheckInTemplate>(\.sortOrder)
        _templates = Query(filter: #Predicate<CheckInTemplate> { $0.isActive }, sort: [sortOrder])
    }

    enum AnalyticsPeriod: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        var id: String { rawValue }
    }

    // MARK: - Computed Properties

    private var liveEntries: [DiaryEntry] {
        allEntries.filter { $0.deletedAt == nil }
    }

    private var periodDays: Int {
        switch period {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    private var periodEntries: [DiaryEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: .now) ?? .now
        return liveEntries.filter { $0.date >= cutoff }
    }

    private var completionRate: Double {
        min(1.0, Double(periodEntries.count) / Double(periodDays))
    }

    private var currentStreak: Int {
        var streak = 0
        var date = Calendar.current.startOfDay(for: .now)
        let entryDates = Set(liveEntries.map { Calendar.current.startOfDay(for: $0.date) })
        while entryDates.contains(date) {
            streak += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86400)
        }
        return streak
    }

    private var longestStreak: Int {
        guard !liveEntries.isEmpty else { return 0 }
        let sorted = liveEntries
            .map { Calendar.current.startOfDay(for: $0.date) }
            .sorted()
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            let diff = Calendar.current.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else if diff > 1 {
                current = 1
            }
        }
        return longest
    }

    private func habitCompletionRate(for template: CheckInTemplate) -> Double {
        let relevant = periodEntries.filter { entry in
            entry.safeCheckInValues.contains { v in
                v.templateId == template.id && isCompleted(v)
            }
        }
        guard periodEntries.count > 0 else { return 0 }
        return Double(relevant.count) / Double(periodEntries.count)
    }

    private func isCompleted(_ value: CheckInValue) -> Bool {
        if let b = value.boolValue { return b }
        if let t = value.textValue { return !t.isEmpty }
        if value.numberValue != nil { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Analytics")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color("textPrimary"))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color("textSecondary"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if liveEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Period picker
                        Picker("Period", selection: $period) {
                            ForEach(AnalyticsPeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 24)

                        // Streak cards
                        HStack(spacing: 16) {
                            StatCard(
                                title: "Current Streak",
                                value: String(currentStreak),
                                unit: currentStreak == 1 ? "day" : "days",
                                icon: "flame.fill",
                                color: Color.orange
                            )
                            StatCard(
                                title: "Longest Streak",
                                value: String(longestStreak),
                                unit: longestStreak == 1 ? "day" : "days",
                                icon: "trophy.fill",
                                color: Color("accentBright")
                            )
                        }
                        .padding(.horizontal, 24)

                        // Completion gauge
                        VStack(spacing: 12) {
                            HStack {
                                Text("Entry Completion")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color("textPrimary"))
                                Spacer()
                                Text(period.rawValue)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color("textSecondary"))
                            }

                            HStack(spacing: 20) {
                                Gauge(value: completionRate) {
                                    EmptyView()
                                } currentValueLabel: {
                                    Text("\(Int(completionRate * 100))%")
                                        .font(.system(.caption2, design: .rounded, weight: .bold))
                                }
                                .gaugeStyle(.accessoryCircular)
                                .tint(Color("accentBright"))
                                .scaleEffect(1.4)
                                .frame(width: 60, height: 60)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(periodEntries.count) of \(periodDays) days")
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                        .foregroundStyle(Color("textPrimary"))
                                    Text("entries written this \(period.rawValue.lowercased())")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color("textSecondary"))
                                }

                                Spacer()
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color("surfaceCard"))
                                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 24)

                        // Habit completion
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Habit Completion")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color("textPrimary"))

                                ForEach(templates) { template in
                                    let rate = habitCompletionRate(for: template)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(template.label)
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(Color("textPrimary"))
                                            Spacer()
                                            Text("\(Int(rate * 100))%")
                                                .font(.system(.caption, design: .rounded, weight: .medium))
                                                .foregroundStyle(rate >= 0.8 ? Color("habitComplete") : Color("textSecondary"))
                                        }
                                        ProgressView(value: rate)
                                            .tint(Color("habitComplete"))
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color("surfaceCard"))
                                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                            )
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Color("backgroundPrimary"))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color("textSecondary").opacity(0.4))
            Text("Start writing to see your analytics")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color("textSecondary"))
            Spacer()
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color("textPrimary"))
                    Text(unit)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
                Text(title)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}
