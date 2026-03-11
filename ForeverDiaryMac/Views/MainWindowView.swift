import SwiftUI
import SwiftData

struct MainWindowView: View {
    @Environment(SyncService.self) private var syncService

    @State private var selectedKey: String? = DiaryEntry.monthDayKey(from: .now)
    @State private var selectedYear: Int = Calendar.current.component(.year, from: .now)
    @State private var showAnalytics = false

    var body: some View {
        NavigationSplitView {
            CalendarSidebarView(
                selectedKey: $selectedKey,
                selectedYear: $selectedYear,
                showAnalytics: $showAnalytics
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } content: {
            if let key = selectedKey {
                DayEntryListView(monthDayKey: key, selectedYear: $selectedYear)
                    .environment(syncService)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            } else {
                Text("Select a date")
                    .foregroundStyle(Color("textSecondary"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color("backgroundPrimary"))
            }
        } detail: {
            if let key = selectedKey {
                EntryEditorContainer(monthDayKey: key, year: selectedYear)
                    .environment(syncService)
            } else {
                Text("No entry selected")
                    .foregroundStyle(Color("textSecondary"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color("backgroundPrimary"))
            }
        }
        .background(Color("backgroundPrimary"))
        .tint(Color("accentBright"))
        .onReceive(NotificationCenter.default.publisher(for: .goToToday)) { _ in
            selectedKey = DiaryEntry.monthDayKey(from: .now)
            selectedYear = Calendar.current.component(.year, from: .now)
        }
        .sheet(isPresented: $showAnalytics) {
            AnalyticsMacView()
                .frame(minWidth: 520, minHeight: 420)
        }
    }
}

// MARK: - Entry Editor Container

struct EntryEditorContainer: View {
    let monthDayKey: String
    let year: Int

    @Query private var entries: [DiaryEntry]

    init(monthDayKey: String, year: Int) {
        self.monthDayKey = monthDayKey
        self.year = year
        let key = monthDayKey
        let yr = year
        _entries = Query(filter: #Predicate<DiaryEntry> {
            $0.monthDayKey == key && $0.year == yr && $0.deletedAt == nil
        })
    }

    var body: some View {
        EntryEditorView(monthDayKey: monthDayKey, year: year, entry: entries.first)
            .id("\(monthDayKey)-\(year)")
    }
}
