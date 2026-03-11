import SwiftUI
import SwiftData

struct DayEntryListView: View {
    let monthDayKey: String
    @Binding var selectedYear: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService

    @Query private var entries: [DiaryEntry]
    @State private var entryToDelete: DiaryEntry?
    @State private var showDeleteAlert = false

    private let currentYear = Calendar.current.component(.year, from: .now)

    init(monthDayKey: String, selectedYear: Binding<Int>) {
        self.monthDayKey = monthDayKey
        _selectedYear = selectedYear
        let key = monthDayKey
        let yearSort = SortDescriptor<DiaryEntry>(\.year, order: .reverse)
        _entries = Query(
            filter: #Predicate<DiaryEntry> { $0.monthDayKey == key && $0.deletedAt == nil },
            sort: [yearSort]
        )
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if !entries.contains(where: { $0.year == currentYear }) {
                    Button {
                        createEntry(year: currentYear)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color("accentBright"))
                            Text("New Entry (\(String(currentYear)))")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(Color("accentBright"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color("accentBright").opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }

                ForEach(entries, id: \.year) { entry in
                    YearCard(entry: entry, isSelected: entry.year == selectedYear)
                        .onTapGesture { selectedYear = entry.year }
                        .contextMenu {
                            Button(role: .destructive) {
                                entryToDelete = entry
                                showDeleteAlert = true
                            } label: {
                                Label("Delete Entry", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color("backgroundPrimary"))
        .navigationTitle(formattedTitle)
        .alert("Delete Entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let e = entryToDelete {
                    let ctx = modelContext
                    Task { await syncService.deleteEntry(e, context: ctx) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let e = entryToDelete {
                Text("This will permanently delete your \(String(e.year)) entry.")
            }
        }
    }

    private func createEntry(year: Int) {
        let parts = monthDayKey.split(separator: "-")
        var comps = DateComponents()
        comps.month = Int(parts[0])
        comps.day = Int(parts.count > 1 ? parts[1] : "1")
        comps.year = year
        let date = Calendar.current.date(from: comps) ?? .now

        let key = monthDayKey
        let tombDesc = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == year }
        )
        if let tombstone = try? modelContext.fetch(tombDesc).first {
            modelContext.delete(tombstone)
        }

        let entry = DiaryEntry(
            monthDayKey: monthDayKey,
            year: year,
            date: date,
            weekday: DiaryEntry.weekdayName(from: date)
        )
        modelContext.insert(entry)
        try? modelContext.save()
        selectedYear = year
        syncService.scheduleDebouncedSync()
    }
}

// MARK: - Year Card

private struct YearCard: View {
    let entry: DiaryEntry
    let isSelected: Bool

    @State private var showGallery = false
    @State private var galleryStartIndex = 0

    private var sortedPhotos: [PhotoAsset] {
        entry.safePhotoAssets.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: year + weekday
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? Color("accentBright") : Color("accentBright").opacity(0.25))
                    .frame(width: 8, height: 8)
                Text(String(entry.year))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color("textPrimary"))
                Spacer()
                Text(entry.weekday)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            // Location
            if let loc = entry.locationText, !loc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 9))
                        .foregroundStyle(Color("textSecondary"))
                    Text(loc)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                        .lineLimit(1)
                }
            }

            // Text preview
            if entry.diaryText.isEmpty {
                Text("No entry yet")
                    .font(.system(.subheadline))
                    .foregroundStyle(Color("textSecondary").opacity(0.6))
                    .italic()
            } else {
                Text(entry.diaryText)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color("textPrimary"))
                    .lineLimit(2)
            }

            // Photo strip
            if !sortedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sortedPhotos.prefix(4)) { photo in
                            if let img = NSImage(data: photo.thumbnailData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture {
                                        galleryStartIndex = sortedPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                        showGallery = true
                                    }
                            }
                        }
                        if sortedPhotos.count > 4 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color("surfaceCard"))
                                    .frame(width: 52, height: 52)
                                Text("+\(sortedPhotos.count - 4)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color("textSecondary"))
                            }
                        }
                    }
                }
            }

            // Stats row
            HStack(spacing: 12) {
                if !sortedPhotos.isEmpty {
                    Label(String(sortedPhotos.count), systemImage: "photo")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
                let total = entry.uniqueCheckInCount
                if total > 0 {
                    Label("\(entry.completedCheckIns)/\(total)", systemImage: "checkmark.circle")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(
                            entry.completedCheckIns == total ? Color("habitComplete") : Color("textSecondary")
                        )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color("accentBright") : .clear, lineWidth: 1.5)
        )
        .sheet(isPresented: $showGallery) {
            MacPhotoGalleryView(photos: sortedPhotos, startIndex: galleryStartIndex)
        }
    }
}
