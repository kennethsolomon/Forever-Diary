import SwiftUI
import SwiftData

struct TimelineView: View {
    let monthDayKey: String

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [DiaryEntry]

    @State private var entryToDelete: DiaryEntry?
    @State private var showDeleteAlert = false

    private let currentYear = Calendar.current.component(.year, from: .now)

    init(monthDayKey: String) {
        self.monthDayKey = monthDayKey
        let key = monthDayKey
        let yearSort = SortDescriptor<DiaryEntry>(\.year, order: .reverse)
        _entries = Query(filter: #Predicate<DiaryEntry> { $0.monthDayKey == key }, sort: [yearSort])
    }

    private var formattedTitle: String {
        let parts = monthDayKey.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]) else { return monthDayKey }
        let formatter = DateFormatter()
        let monthName = formatter.shortMonthSymbols[month - 1]
        return "\(monthName) \(day)"
    }

    private var hasCurrentYearEntry: Bool {
        entries.contains { $0.year == currentYear }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !hasCurrentYearEntry {
                    NavigationLink {
                        EntryDetailView(monthDayKey: monthDayKey, year: currentYear)
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

                ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                    NavigationLink {
                        EntryDetailView(monthDayKey: entry.monthDayKey, year: entry.year)
                    } label: {
                        YearCard(entry: entry)
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: entries.count)
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

                if entries.isEmpty && hasCurrentYearEntry == false {
                    Text("No entries for this date yet.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                        .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(Color("backgroundPrimary"))
        .navigationTitle(formattedTitle)
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let entryToDelete {
                    modelContext.delete(entryToDelete)
                    try? modelContext.save()
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

// MARK: - Year Card

struct YearCard: View {
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
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color("textPrimary"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
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
