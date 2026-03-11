import SwiftUI
import SwiftData

struct CalendarSidebarView: View {
    @Binding var selectedKey: String?
    @Binding var selectedYear: Int
    @Binding var showAnalytics: Bool

    @State private var displayMonth: Int = Calendar.current.component(.month, from: .now)
    @State private var displayYear: Int = Calendar.current.component(.year, from: .now)

    private let weekdayAbbrevs = ["S", "M", "T", "W", "T", "F", "S"]
    private var todayMonth: Int { Calendar.current.component(.month, from: .now) }
    private var todayYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        VStack(spacing: 0) {
            // Month + year header with navigation
            HStack(alignment: .center) {
                Button { prevMonth() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color("textSecondary"))
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(Calendar.current.monthSymbols[displayMonth - 1])
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color("textPrimary"))
                    Text(String(displayYear))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }

                Spacer()

                Button { nextMonth() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color("textSecondary"))
                }
                .buttonStyle(.plain)
                .disabled(displayYear > todayYear || (displayYear == todayYear && displayMonth >= todayMonth))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Day-of-week abbreviations
            HStack(spacing: 0) {
                ForEach(weekdayAbbrevs.indices, id: \.self) { i in
                    Text(weekdayAbbrevs[i])
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            // Month grid
            MacMonthGridView(
                month: displayMonth,
                year: displayYear,
                selectedKey: $selectedKey,
                selectedYear: $selectedYear
            )
            .padding(.horizontal, 6)

            Spacer()

            Divider()

            // Analytics button
            Button {
                showAnalytics = true
            } label: {
                Label("Analytics", systemImage: "chart.bar")
                    .font(.system(.subheadline, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color("textSecondary"))
        }
        .background(Color("backgroundPrimary"))
        .onReceive(NotificationCenter.default.publisher(for: .goToToday)) { _ in
            displayMonth = Calendar.current.component(.month, from: .now)
            displayYear = Calendar.current.component(.year, from: .now)
        }
    }

    private func prevMonth() {
        if displayMonth == 1 {
            displayMonth = 12
            displayYear -= 1
        } else {
            displayMonth -= 1
        }
    }

    private func nextMonth() {
        guard displayYear < todayYear || (displayYear == todayYear && displayMonth < todayMonth) else { return }
        if displayMonth == 12 {
            displayMonth = 1
            displayYear += 1
        } else {
            displayMonth += 1
        }
    }
}

// MARK: - Month Grid

struct MacMonthGridView: View {
    let month: Int
    let year: Int
    @Binding var selectedKey: String?
    @Binding var selectedYear: Int

    @Query private var entries: [DiaryEntry]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var todayMonth: Int { Calendar.current.component(.month, from: .now) }
    private var todayDay: Int { Calendar.current.component(.day, from: .now) }
    private var todayYear: Int { Calendar.current.component(.year, from: .now) }

    init(month: Int, year: Int, selectedKey: Binding<String?>, selectedYear: Binding<Int>) {
        self.month = month
        self.year = year
        _selectedKey = selectedKey
        _selectedYear = selectedYear
        let prefix = String(format: "%02d-", month)
        let yr = year
        _entries = Query(filter: #Predicate<DiaryEntry> {
            $0.monthDayKey.starts(with: prefix) && $0.year == yr && $0.deletedAt == nil
        })
    }

    private var entryKeys: Set<String> { Set(entries.map { $0.monthDayKey }) }

    private var daysInMonth: Int {
        var comps = DateComponents(); comps.month = month; comps.year = year
        guard let date = Calendar.current.date(from: comps),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    private var weekdayOffset: Int {
        var comps = DateComponents(); comps.month = month; comps.day = 1; comps.year = year
        guard let date = Calendar.current.date(from: comps) else { return 0 }
        return (Calendar.current.component(.weekday, from: date) - Calendar.current.firstWeekday + 7) % 7
    }

    var body: some View {
        let keys = entryKeys
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(0..<(weekdayOffset + daysInMonth), id: \.self) { index in
                if index < weekdayOffset {
                    Color.clear.frame(height: 26)
                } else {
                    let day = index - weekdayOffset + 1
                    let key = String(format: "%02d-%02d", month, day)
                    let isToday = month == todayMonth && day == todayDay && year == todayYear
                    let isSelected = selectedKey == key
                    let hasEntry = keys.contains(key)

                    Button {
                        selectedKey = key
                        selectedYear = year
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color("accentBright") : (isToday ? Color("accentBright").opacity(0.18) : .clear))
                                .frame(width: 22, height: 22)

                            VStack(spacing: 1) {
                                Text("\(day)")
                                    .font(.system(size: 10, weight: isToday ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : (isToday ? Color("accentBright") : Color("textPrimary")))
                                if hasEntry && !isSelected {
                                    Circle()
                                        .fill(Color("accentBright"))
                                        .frame(width: 3, height: 3)
                                }
                            }
                        }
                        .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
