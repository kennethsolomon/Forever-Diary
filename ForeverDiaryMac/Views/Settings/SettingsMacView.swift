import SwiftUI
import SwiftData

struct SettingsMacView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(SpeechService.self) private var speechService

    @AppStorage("appTheme") private var storedTheme: String = AppTheme.system.rawValue
    @State private var showSignOutAlert = false

    var body: some View {
        TabView {
            AccountTab(showSignOutAlert: $showSignOutAlert)
                .tabItem { Label("Account", systemImage: "person.circle") }

            AppearanceTab(storedTheme: $storedTheme)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            HabitsTab()
                .tabItem { Label("Habits", systemImage: "checkmark.circle") }

            SpeechTab()
                .tabItem { Label("Speech", systemImage: "mic.circle") }

            SyncTab()
                .tabItem { Label("Sync", systemImage: "icloud") }
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(Color("backgroundPrimary"))
        .environment(syncService)
        .environment(cognitoAuth)
        .environment(speechService)
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                cognitoAuth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to access your diary.")
        }
    }
}

// MARK: - Account Tab

private struct AccountTab: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Binding var showSignOutAlert: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color("accentBright"))

                if let email = cognitoAuth.userEmail {
                    Text(email)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color("textPrimary"))
                }

                Text("Signed in")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            Spacer()

            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                Text("Sign Out")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("destructive"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color("destructive").opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("backgroundPrimary"))
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @Binding var storedTheme: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color("accentBright"))

                Text("Appearance")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))

                Picker("Theme", selection: $storedTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("backgroundPrimary"))
    }
}

// MARK: - Habits Tab

private struct HabitsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService

    @Query(filter: #Predicate<CheckInTemplate> { _ in true },
           sort: [SortDescriptor<CheckInTemplate>(\.sortOrder)])
    private var templates: [CheckInTemplate]

    @State private var showAddSheet = false
    @State private var templateToEdit: CheckInTemplate?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Habit Templates")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Habit", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("accentBright"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if templates.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color("textSecondary").opacity(0.4))
                    Text("No habits yet. Add one above.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                    Spacer()
                }
            } else {
                List {
                    ForEach(templates) { template in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.label)
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    .foregroundStyle(Color("textPrimary"))
                                Text(template.type.displayName)
                                    .font(.system(.caption2, design: .rounded))
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
                            Button("Edit") {
                                templateToEdit = template
                            }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color("accentBright"))
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: reorderTemplates)
                    .onDelete(perform: deleteTemplates)
                }
                .listStyle(.bordered)
            }
        }
        .background(Color("backgroundPrimary"))
        .sheet(isPresented: $showAddSheet) {
            MacTemplateEditorSheet(template: nil) { label, type, isActive in
                addTemplate(label: label, type: type, isActive: isActive)
            }
        }
        .sheet(item: $templateToEdit) { template in
            MacTemplateEditorSheet(template: template) { label, type, isActive in
                template.label = label
                template.type = type
                template.isActive = isActive
                template.updatedAt = .now
                template.syncStatus = SyncStatus.pending
                try? modelContext.save()
                syncService.scheduleDebouncedSync()
            }
        }
    }

    private func addTemplate(label: String, type: CheckInFieldType, isActive: Bool) {
        let maxOrder = templates.map { $0.sortOrder }.max() ?? -1
        let template = CheckInTemplate(label: label, type: type, isActive: isActive, sortOrder: maxOrder + 1)
        modelContext.insert(template)
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var ordered = templates.sorted { $0.sortOrder < $1.sortOrder }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in ordered.enumerated() {
            template.sortOrder = index
            template.updatedAt = .now
            template.syncStatus = SyncStatus.pending
        }
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
    }

    private func deleteTemplates(at offsets: IndexSet) {
        let sorted = templates.sorted { $0.sortOrder < $1.sortOrder }
        for index in offsets {
            let template = sorted[index]
            Task {
                await syncService.deleteTemplate(template, context: modelContext)
            }
        }
    }
}

// MARK: - Speech Tab

private struct SpeechTab: View {
    @Environment(SpeechService.self) private var speechService

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color("accentBright"))

                Text("Speech Engine")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))

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
                .frame(maxWidth: 300)

                Text("The other engine is used as fallback if the primary fails.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                    .multilineTextAlignment(.center)

                Divider()
                    .frame(maxWidth: 300)

                // Language
                HStack {
                    Text("Language")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textPrimary"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { speechService.languageIdentifier },
                        set: { speechService.languageIdentifier = $0 }
                    )) {
                        Text("Auto-detect").tag("auto")
                        ForEach(SpeechService.whisperSupportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .frame(maxWidth: 200)
                }
                .frame(maxWidth: 300)

                // WhisperKit model status
                if speechService.engineChoice == .whisperKit || speechService.whisperModelState == .downloaded {
                    Divider()
                        .frame(maxWidth: 300)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WhisperKit Model")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color("textPrimary"))
                            Text("large-v3-turbo (~809 MB)")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color("textSecondary"))
                        }
                        Spacer()
                        whisperModelStatus
                    }
                    .frame(maxWidth: 300)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("backgroundPrimary"))
    }

    @ViewBuilder
    private var whisperModelStatus: some View {
        switch speechService.whisperModelState {
        case .notDownloaded:
            Button("Download") {
                Task { await speechService.downloadWhisperModel() }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color("accentBright"))
            .buttonStyle(.plain)
        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading...")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        case .downloaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color("habitComplete"))
                    .font(.caption)
                Button("Delete", role: .destructive) {
                    speechService.deleteWhisperModel()
                }
                .font(.system(.caption, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(Color("destructive"))
            }
        case .error(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text(msg)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color("destructive"))
                Button("Retry") {
                    Task { await speechService.downloadWhisperModel() }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color("accentBright"))
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Sync Tab

private struct SyncTab: View {
    @Environment(SyncService.self) private var syncService
    @Environment(NetworkMonitor.self) private var networkMonitor

    private var lastSyncText: String {
        guard let date = syncService.lastSyncDate else { return "Never synced" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: !networkMonitor.isConnected ? "wifi.slash" : syncService.isSyncing ? "icloud.and.arrow.up" : "icloud.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(!networkMonitor.isConnected ? Color("textSecondary") : syncService.lastError != nil ? Color("destructive") : Color("accentBright"))

                if !networkMonitor.isConnected {
                    Text("Offline")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                } else if syncService.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color("textSecondary"))
                    }
                } else {
                    Text("Last synced: \(lastSyncText)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }

                if networkMonitor.isConnected, let error = syncService.lastError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("destructive"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await syncService.syncAll() }
                } label: {
                    Text("Sync Now")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 160)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(syncService.isSyncing || !networkMonitor.isConnected ? Color("textSecondary") : Color("accentBright"))
                        )
                }
                .buttonStyle(.plain)
                .disabled(syncService.isSyncing || !networkMonitor.isConnected)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("backgroundPrimary"))
    }
}

// MARK: - Template Editor Sheet

struct MacTemplateEditorSheet: View {
    let template: CheckInTemplate?
    let onSave: (String, CheckInFieldType, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var type: CheckInFieldType = .boolean
    @State private var isActive: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Label", text: $label)
                    Picker("Type", selection: $type) {
                        ForEach(CheckInFieldType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                }
            }
            .navigationTitle(template == nil ? "New Habit" : "Edit Habit")
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
                if let t = template {
                    label = t.label
                    type = t.type
                    isActive = t.isActive
                }
            }
        }
        .frame(minWidth: 320, minHeight: 240)
    }
}
