import SwiftUI
import SwiftData

// MARK: - Day Summary Sheet

struct DaySummarySheet: View {
    let monthDayKey: String
    let onNavigate: (EntryDestination) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DiaryEntry]

    @State private var entryToDelete: DiaryEntry?
    @State private var showDeleteAlert = false

    private let currentYear = Calendar.current.component(.year, from: .now)

    init(monthDayKey: String, onNavigate: @escaping (EntryDestination) -> Void) {
        self.monthDayKey = monthDayKey
        self.onNavigate = onNavigate
        let key = monthDayKey
        let yearSort = SortDescriptor<DiaryEntry>(\.year, order: .reverse)
        _entries = Query(filter: #Predicate<DiaryEntry> { $0.monthDayKey == key }, sort: [yearSort])
    }

    private var formattedTitle: String {
        let parts = monthDayKey.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              month >= 1, month <= 12 else { return monthDayKey }
        let formatter = DateFormatter()
        let monthName = formatter.shortMonthSymbols[month - 1]
        return "\(monthName) \(day)"
    }

    private var hasCurrentYearEntry: Bool {
        entries.contains { $0.year == currentYear }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !hasCurrentYearEntry {
                        Button {
                            createAndNavigate()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Entry (\(String(currentYear)))")
                                    .font(.system(.headline, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color("accentBright"))
                            )
                        }
                        .padding(.bottom, 4)
                    }

                    ForEach(entries, id: \.persistentModelID) { entry in
                        Button {
                            onNavigate(EntryDestination(monthDayKey: entry.monthDayKey, year: entry.year))
                        } label: {
                            YearSummaryCard(entry: entry)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showDeleteAlert = true
                            } label: {
                                Label("Delete Entry", systemImage: "trash")
                            }
                        }
                    }

                    if entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(Color("textSecondary").opacity(0.4))
                            Text("No entries for this date yet.")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color("textSecondary"))
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(20)
            }
            .background(Color("backgroundPrimary"))
            .navigationTitle(formattedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }
            .alert("Delete Entry?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let entryToDelete {
                        modelContext.delete(entryToDelete)
                        do {
                            try modelContext.save()
                        } catch {
                            print("[ForeverDiary] Delete failed: \(error.localizedDescription)")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let entryToDelete {
                    Text("This will permanently delete your \(entryToDelete.year) entry and all its photos and check-ins.")
                }
            }
        }
    }

    private func createAndNavigate() {
        let parts = monthDayKey.split(separator: "-")
        var components = DateComponents()
        components.month = Int(parts[0])
        components.day = Int(parts[1])
        components.year = currentYear
        let date = Calendar.current.date(from: components) ?? .now

        let newEntry = DiaryEntry(
            monthDayKey: monthDayKey,
            year: currentYear,
            date: date,
            weekday: DiaryEntry.weekdayName(from: date)
        )
        modelContext.insert(newEntry)
        try? modelContext.save()

        onNavigate(EntryDestination(monthDayKey: monthDayKey, year: currentYear))
    }
}

// MARK: - Year Summary Card

struct YearSummaryCard: View {
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(entry.year))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color("textPrimary"))

                Text(entry.weekday)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))

                Spacer()
            }

            if let location = entry.locationText, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                    Text(location)
                        .font(.system(.caption, design: .rounded))
                }
                .foregroundStyle(Color("textSecondary"))
            }

            if !entry.diaryText.isEmpty {
                Text(entry.diaryText)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color("textPrimary"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if !entry.safePhotoAssets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(entry.safePhotoAssets.sorted(by: { $0.createdAt < $1.createdAt }).prefix(5)), id: \.id) { photo in
                            if let uiImage = UIImage(data: photo.thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        if entry.safePhotoAssets.count > 5 {
                            Text("+\(entry.safePhotoAssets.count - 5)")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(Color("textSecondary"))
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color("surfaceCard"))
                                )
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                if !entry.safePhotoAssets.isEmpty {
                    Label("\(entry.safePhotoAssets.count)", systemImage: "photo")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }

                let total = entry.safeCheckInValues.count
                if total > 0 {
                    Label(
                        "\(entry.completedCheckIns)/\(total)",
                        systemImage: "checkmark.circle"
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}
