import SwiftUI
import SwiftData

struct EntryDestination: Hashable {
    let monthDayKey: String
    let year: Int
}

struct CalendarBrowserView: View {
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: .now)
    @State private var navigationPath = NavigationPath()

    private let months = Calendar.current.monthSymbols

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                TabView(selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        MonthPageView(month: month, navigationPath: $navigationPath)
                            .tag(month)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color("backgroundPrimary"))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { key in
                DayTimelineView(monthDayKey: key, navigationPath: $navigationPath)
            }
            .navigationDestination(for: EntryDestination.self) { dest in
                EntryDetailView(monthDayKey: dest.monthDayKey, year: dest.year)
            }
            .safeAreaInset(edge: .top) {
                monthSelector
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Color("backgroundPrimary"))
            }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                withAnimation { selectedMonth = max(1, selectedMonth - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(selectedMonth > 1 ? Color("accentSlate") : Color("textSecondary").opacity(0.3))
            }
            .disabled(selectedMonth <= 1)

            Spacer()

            Text(months[selectedMonth - 1].uppercased())
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(Color("textPrimary"))
                .animation(.none, value: selectedMonth)

            Spacer()

            Button {
                withAnimation { selectedMonth = min(12, selectedMonth + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(selectedMonth < 12 ? Color("accentSlate") : Color("textSecondary").opacity(0.3))
            }
            .disabled(selectedMonth >= 12)
        }
    }
}

// MARK: - Month Page

struct MonthPageView: View {
    let month: Int
    @Binding var navigationPath: NavigationPath

    @Query private var entries: [DiaryEntry]

    init(month: Int, navigationPath: Binding<NavigationPath>) {
        self.month = month
        self._navigationPath = navigationPath
        let prefix = String(format: "%02d-", month)
        _entries = Query(filter: #Predicate<DiaryEntry> { $0.monthDayKey.starts(with: prefix) })
    }

    private var daysInMonth: Int {
        var components = DateComponents()
        components.month = month
        components.year = Calendar.current.component(.year, from: .now)
        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    private let todayMonth = Calendar.current.component(.month, from: .now)
    private let todayDay = Calendar.current.component(.day, from: .now)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let key = String(format: "%02d-%02d", month, day)
                    let yearEntries = entries.filter { $0.monthDayKey == key }
                    let isToday = month == todayMonth && day == todayDay

                    Button {
                        navigationPath.append(key)
                    } label: {
                        DayRow(day: day, yearCount: yearEntries.count, isToday: isToday)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Day Row

struct DayRow: View {
    let day: Int
    let yearCount: Int
    let isToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isToday {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("accentBright"))
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }

            Text("\(day)")
                .font(.system(.body, design: .rounded, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color("accentBright") : Color("textPrimary"))
                .frame(width: 30, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<yearCount, id: \.self) { _ in
                    Circle()
                        .fill(Color("accentSlate"))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(Color("textSecondary").opacity(0.4))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color("accentBright").opacity(0.06) : .clear)
        )
    }
}
