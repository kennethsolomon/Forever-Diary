import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(SpeechService.self) private var speechService
    @Query(sort: \CheckInTemplate.sortOrder) private var templates: [CheckInTemplate]

    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @State private var showAddTemplate = false
    @State private var templateToEdit: CheckInTemplate?
    @State private var templateToDelete: CheckInTemplate?
    @State private var showDeleteAlert = false
    @State private var showSignOutAlert = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                speechSection
                habitTemplatesSection
                syncSection
                aboutSection
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Settings")
            .background(Color("backgroundPrimary"))
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
                    template.updatedAt = .now
                    template.syncStatus = SyncStatus.pending
                    try? modelContext.save()
                    syncService.scheduleDebouncedSync()
                }
            }
            .alert("Delete Template?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let templateToDelete {
                        Task { await syncService.deleteTemplate(templateToDelete, context: modelContext) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This won't delete existing check-in data, but the template will no longer appear on new entries.")
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.circle")
                    .font(.system(.body))
                    .foregroundStyle(Color("textPrimary"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cognitoAuth.userEmail ?? "Account")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color("textPrimary"))
                    Text("Signed in")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }

            Button("Sign Out", role: .destructive) {
                showSignOutAlert = true
            }
            .font(.system(.body, design: .rounded))
        } header: {
            Text("Account")
        }
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                cognitoAuth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your diary.")
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

    // MARK: - Speech

    private var speechSection: some View {
        Section {
            Picker("Engine", selection: Binding(
                get: { speechService.engineChoice },
                set: { newValue in
                    speechService.engineChoice = newValue
                    if newValue == .whisperKit && speechService.whisperModelState == .notDownloaded {
                        Task { await speechService.downloadWhisperModel() }
                    }
                }
            )) {
                ForEach(SpeechEngineType.allCases, id: \.rawValue) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink {
                LanguagePickerView()
                    .environment(speechService)
            } label: {
                HStack {
                    Text("Language")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Text(speechService.currentLocaleDisplayName)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }

            if speechService.engineChoice == .whisperKit || speechService.whisperModelState == .downloaded {
                whisperModelRow
            }
        } header: {
            Text("Speech")
        } footer: {
            Text("The other engine is used as fallback if the primary fails.")
        }
    }

    private var whisperModelRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WhisperKit Model")
                    .font(.system(.body, design: .rounded))
                Text("large-v3-turbo (~809 MB)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
            Spacer()
            switch speechService.whisperModelState {
            case .notDownloaded:
                Button("Download") {
                    Task { await speechService.downloadWhisperModel() }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color("accentBright"))
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            case .downloaded:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color("habitComplete"))
                    Button("Delete", role: .destructive) {
                        speechService.deleteWhisperModel()
                    }
                    .font(.system(.caption, design: .rounded))
                }
            case .error(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color("destructive"))
                    Button("Retry") {
                        Task { await speechService.downloadWhisperModel() }
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("accentBright"))
                }
            }
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
            HStack {
                Text("Habit Templates")
                Spacer()
                Button {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {
                    Image(systemName: editMode == .active ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundStyle(Color("accentBright"))
                        .font(.system(size: 16))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }
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
                } else if !networkMonitor.isConnected {
                    Text("Offline")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
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
            .disabled(syncService.isSyncing || !networkMonitor.isConnected)
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
        syncService.scheduleDebouncedSync()
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var ordered = templates.sorted { $0.sortOrder < $1.sortOrder }
        ordered.move(fromOffsets: source, toOffset: destination)
        let now = Date.now
        for (index, template) in ordered.enumerated() {
            template.sortOrder = index
            template.updatedAt = now
            template.syncStatus = SyncStatus.pending
        }
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
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
