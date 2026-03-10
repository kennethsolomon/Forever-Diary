import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query(sort: \CheckInTemplate.sortOrder) private var templates: [CheckInTemplate]

    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @State private var showAddTemplate = false
    @State private var templateToEdit: CheckInTemplate?
    @State private var templateToDelete: CheckInTemplate?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                habitTemplatesSection
                syncSection
                aboutSection
            }
            .navigationTitle("Settings")
            .background(Color("backgroundPrimary"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddTemplate) {
                TemplateEditorSheet(template: nil) { label, type, isActive in
                    addTemplate(label: label, type: type, isActive: isActive)
                }
            }
            .sheet(item: $templateToEdit) { template in
                TemplateEditorSheet(template: template) { label, type, isActive in
                    template.label = label
                    template.type = type
                    template.isActive = isActive
                    try? modelContext.save()
                }
            }
            .alert("Delete Template?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let templateToDelete {
                        modelContext.delete(templateToDelete)
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This won't delete existing check-in data, but the template will no longer appear on new entries.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Habit Templates

    private var habitTemplatesSection: some View {
        Section {
            ForEach(templates) { template in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.label)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color("textPrimary"))
                        Text(template.type.displayName)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color("textSecondary"))
                    }

                    Spacer()

                    if template.isActive {
                        Text("Active")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(Color("habitComplete"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color("habitComplete").opacity(0.12))
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { templateToEdit = template }
            }
            .onMove(perform: reorderTemplates)
            .onDelete(perform: deleteTemplates)

            Button {
                showAddTemplate = true
            } label: {
                Label("Add Template", systemImage: "plus.circle")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color("accentBright"))
            }
        } header: {
            Text("Habit Templates")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            HStack {
                Label("Cloud Sync", systemImage: "cloud")
                    .font(.system(.body, design: .rounded))
                Spacer()
                if syncService.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Active")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Text("Last Synced")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Text(lastSync, style: .relative)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                    Text("ago")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }

            if let error = syncService.lastError {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await syncService.syncAll() }
            } label: {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    if syncService.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(syncService.isSyncing)
        } header: {
            Text("Sync")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .font(.system(.body, design: .rounded))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
            HStack {
                Text("Build")
                    .font(.system(.body, design: .rounded))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Actions

    private func addTemplate(label: String, type: CheckInFieldType, isActive: Bool) {
        let maxOrder = templates.map(\.sortOrder).max() ?? -1
        let template = CheckInTemplate(label: label, type: type, isActive: isActive, sortOrder: maxOrder + 1)
        modelContext.insert(template)
        try? modelContext.save()
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var ordered = templates.sorted { $0.sortOrder < $1.sortOrder }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in ordered.enumerated() {
            template.sortOrder = index
        }
        try? modelContext.save()
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            templateToDelete = templates[index]
            showDeleteAlert = true
        }
    }
}

// MARK: - Template Editor Sheet

struct TemplateEditorSheet: View {
    let template: CheckInTemplate?
    let onSave: (String, CheckInFieldType, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var type: CheckInFieldType = .text
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                    Picker("Type", selection: $type) {
                        ForEach(CheckInFieldType.allCases) { fieldType in
                            Text(fieldType.displayName).tag(fieldType)
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave(label.trimmingCharacters(in: .whitespaces), type, isActive)
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let template {
                    label = template.label
                    type = template.type
                    isActive = template.isActive
                }
            }
        }
        .presentationDetents([.medium])
    }
}
