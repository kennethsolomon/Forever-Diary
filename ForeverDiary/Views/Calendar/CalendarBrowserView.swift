import SwiftUI
import SwiftData

// MARK: - Calendar Browser

struct CalendarBrowserView: View {
    @State private var navigationPath = NavigationPath()
    @State private var sheetItem: DaySheetItem?
    @State private var pendingNavigation: EntryDestination?

    private let currentMonth = Calendar.current.component(.month, from: .now)

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 32) {
                        ForEach(1...12, id: \.self) { month in
                            MonthSection(month: month) { key in
                                sheetItem = DaySheetItem(id: key)
                            }
                            .id("month-\(month)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation(.none) {
                            proxy.scrollTo("month-\(currentMonth)", anchor: .top)
                        }
                    }
                }
            }
            .background(Color("backgroundPrimary"))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: EntryDestination.self) { dest in
                EntryDetailView(monthDayKey: dest.monthDayKey, year: dest.year)
            }
            .sheet(item: $sheetItem, onDismiss: {
                if let dest = pendingNavigation {
                    pendingNavigation = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        navigationPath.append(dest)
                    }
                }
            }) { item in
                DaySummarySheet(monthDayKey: item.monthDayKey) { dest in
                    pendingNavigation = dest
                    sheetItem = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Month Section

struct MonthSection: View {
    let month: Int
    let onDayTapped: (String) -> Void

    @Query private var entries: [DiaryEntry]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let todayMonth = Calendar.current.component(.month, from: .now)
    private let todayDay = Calendar.current.component(.day, from: .now)

    init(month: Int, onDayTapped: @escaping (String) -> Void) {
        self.month = month
        self.onDayTapped = onDayTapped
        let prefix = String(format: "%02d-", month)
        _entries = Query(filter: #Predicate<DiaryEntry> { $0.monthDayKey.starts(with: prefix) && $0.deletedAt == nil })
    }

    private var daysInMonth: Int {
        var components = DateComponents()
        components.month = month
        components.year = Calendar.current.component(.year, from: .now)
        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    private var weekdayOffset: Int {
        var components = DateComponents()
        components.month = month
        components.day = 1
        components.year = Calendar.current.component(.year, from: .now)
        guard let date = Calendar.current.date(from: components) else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday - Calendar.current.firstWeekday + 7) % 7
    }

    private var entriesByDay: [String: [DiaryEntry]] {
        Dictionary(grouping: entries, by: \.monthDayKey)
    }

    var body: some View {
        let grouped = entriesByDay
        VStack(spacing: 12) {
            Text(Calendar.current.monthSymbols[month - 1])
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color("textPrimary"))
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<(weekdayOffset + daysInMonth), id: \.self) { index in
                    if index < weekdayOffset {
                        Color.clear
                            .aspectRatio(3/4, contentMode: .fit)
                    } else {
                        let day = index - weekdayOffset + 1
                        let key = String(format: "%02d-%02d", month, day)
                        let dayEntries = grouped[key] ?? []
                        let allPhotos = dayEntries.flatMap { $0.safePhotoAssets }
                        let thumbnails = Array(allPhotos.prefix(4).map { $0.thumbnailData })
                        let isToday = month == todayMonth && day == todayDay

                        DayCell(
                            day: day,
                            isToday: isToday,
                            thumbnails: thumbnails,
                            totalPhotoCount: allPhotos.count,
                            totalEntries: dayEntries.count
                        ) {
                            onDayTapped(key)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let day: Int
    let isToday: Bool
    let thumbnails: [Data]
    let totalPhotoCount: Int
    let totalEntries: Int
    let onTap: () -> Void

    private var isStacked: Bool { totalEntries > 1 || totalPhotoCount >= 3 }
    private var hasPhoto: Bool { !thumbnails.isEmpty }

    var body: some View {
        Button(action: onTap) {
            cardContent
                .clipped()
        }
        .aspectRatio(3/4, contentMode: .fit)
        .buttonStyle(ScaleButtonStyle())
        .overlay(alignment: .topTrailing) {
            if isStacked {
                Text("\(totalEntries)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color("accentBright")))
                    .offset(x: 3, y: -3)
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        ZStack(alignment: .top) {
            if isStacked {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("surfaceCard").opacity(0.45))
                    .rotationEffect(.degrees(2.5))
                    .offset(y: 6)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("surfaceCard").opacity(0.7))
                    .rotationEffect(.degrees(-1.5))
                    .offset(y: 3)
            }
            topCard
        }
    }

    @ViewBuilder
    private var topCard: some View {
        if hasPhoto {
            ZStack(alignment: .bottomLeading) {
                thumbnailImage(thumbnails[0])
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color("accentBright"), lineWidth: 1.5)
                }
                Text("\(day)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .padding(4)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("surfaceCard"))
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color("accentBright"), lineWidth: 1.5)
                }
                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color("accentBright") : Color("textPrimary"))
                    if totalEntries > 0 {
                        Circle()
                            .fill(Color("accentBright"))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
    }

    private func thumbnailImage(_ data: Data) -> some View {
        Color("surfaceCard")
            .overlay(
                Group {
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
