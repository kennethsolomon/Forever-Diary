import SwiftUI
import SwiftData

struct EntryListView: View {
    @Query(sort: \DiaryEntry.date, order: .reverse) private var entries: [DiaryEntry]

    var body: some View {
        List(entries.filter { $0.deletedAt == nil }, id: \.persistentModelID) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.weekday + ", " + String(entry.year))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                if !entry.diaryText.isEmpty {
                    Text(entry.diaryText)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .navigationTitle("Entries")
    }
}
