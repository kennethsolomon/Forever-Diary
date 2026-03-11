import SwiftUI
import SwiftData

struct CheckInSectionView: View {
    let entry: DiaryEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query private var templates: [CheckInTemplate]

    init(entry: DiaryEntry) {
        self.entry = entry
        let sortOrder = SortDescriptor<CheckInTemplate>(\.sortOrder)
        _templates = Query(filter: #Predicate<CheckInTemplate> { $0.isActive }, sort: [sortOrder])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Check-in")
                .font(.system(.headline, design: .rounded))

            ForEach(templates) { template in
                checkInRow(for: template)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func checkInRow(for template: CheckInTemplate) -> some View {
        let value = entry.safeCheckInValues.first(where: { $0.templateId == template.id })
        HStack {
            Text(template.label)
                .font(.system(.subheadline, design: .rounded))
                .frame(width: 120, alignment: .leading)

            Spacer()

            switch template.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { value?.boolValue ?? false },
                    set: { newVal in updateCheckIn(template: template, bool: newVal) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

            case .text:
                TextField("...", text: Binding(
                    get: { value?.textValue ?? "" },
                    set: { newVal in updateCheckIn(template: template, text: newVal) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

            case .number:
                TextField("0", value: Binding(
                    get: { value?.numberValue ?? 0 },
                    set: { newVal in updateCheckIn(template: template, number: newVal) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        }
    }

    private func updateCheckIn(template: CheckInTemplate, bool: Bool? = nil, text: String? = nil, number: Double? = nil) {
        if let existing = entry.safeCheckInValues.first(where: { $0.templateId == template.id }) {
            existing.boolValue = bool ?? existing.boolValue
            existing.textValue = text ?? existing.textValue
            existing.numberValue = number ?? existing.numberValue
            existing.updatedAt = .now
        } else {
            let value = CheckInValue(templateId: template.id, boolValue: bool, textValue: text, numberValue: number)
            value.entry = entry
            modelContext.insert(value)
        }
        entry.updatedAt = .now
        entry.syncStatus = SyncStatus.pending
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
    }
}
