import SwiftUI
import SwiftData

struct EntryDestination: Hashable {
    let monthDayKey: String
    let year: Int
}

struct DaySheetItem: Identifiable {
    let id: String
    var monthDayKey: String { id }
}

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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let todayMonth = Calendar.current.component(.month, from: .now)
    private let todayDay = Calendar.current.component(.day, from: .now)

    init(month: Int, onDayTapped: @escaping (String) -> Void) {
        self.month = month
        self.onDayTapped = onDayTapped
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

    private var weekdayOffset: Int {
        var components = DateComponents()
        components.month = month
        components.day = 1
        components.year = Calendar.current.component(.year, from: .now)
        guard let date = Calendar.current.date(from: components) else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday - Calendar.current.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(Calendar.current.monthSymbols[month - 1])
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color("textPrimary"))
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<weekdayOffset, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    let key = String(format: "%02d-%02d", month, day)
                    let dayEntries = entries.filter { $0.monthDayKey == key }
                    let allPhotos = dayEntries.flatMap { $0.safePhotoAssets }
                    let thumbnails = Array(allPhotos.prefix(4).map { $0.thumbnailData })
                    let isToday = month == todayMonth && day == todayDay

                    DayCell(
                        day: day,
                        isToday: isToday,
                        hasEntries: !dayEntries.isEmpty,
                        thumbnails: thumbnails,
                        totalPhotoCount: allPhotos.count
                    ) {
                        onDayTapped(key)
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
    let hasEntries: Bool
    let thumbnails: [Data]
    let totalPhotoCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if thumbnails.isEmpty {
                    Circle()
                        .fill(hasEntries ? Color("accentBright").opacity(0.1) : Color.clear)

                    Text("\(day)")
                        .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color("accentBright") : Color("textPrimary"))
                } else {
                    collageView
                        .clipShape(Circle())

                    Text("\(day)")
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)

                    if isToday {
                        Circle()
                            .stroke(Color("accentBright"), lineWidth: 2.5)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                if totalPhotoCount > 4 {
                    Text("\(totalPhotoCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color("accentBright")))
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var collageView: some View {
        switch thumbnails.count {
        case 1:
            thumbnailImage(thumbnails[0])
        case 2:
            HStack(spacing: 1) {
                thumbnailImage(thumbnails[0])
                thumbnailImage(thumbnails[1])
            }
        case 3:
            HStack(spacing: 1) {
                thumbnailImage(thumbnails[0])
                VStack(spacing: 1) {
                    thumbnailImage(thumbnails[1])
                    thumbnailImage(thumbnails[2])
                }
            }
        default:
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    thumbnailImage(thumbnails[0])
                    thumbnailImage(thumbnails[1])
                }
                HStack(spacing: 1) {
                    thumbnailImage(thumbnails[2])
                    thumbnailImage(thumbnails.count > 3 ? thumbnails[3] : thumbnails[2])
                }
            }
        }
    }

    private func thumbnailImage(_ data: Data) -> some View {
        Group {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color("surfaceCard")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
