import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @FocusState private var isTextEditorFocused: Bool
    @State private var isViewMode = false
    @State private var diaryText = ""
    @State private var showSavedIndicator = false
    @State private var saveTask: Task<Void, Never>?
    @State private var entry: DiaryEntry?
    @State private var showLocationEditor = false
    @State private var showPhotoPicker = false

    private let today = Date.now
    private var todayKey: String { DiaryEntry.monthDayKey(from: today) }
    private var todayYear: Int { DiaryEntry.year(from: today) }

    @Query private var templates: [CheckInTemplate]

    init() {
        let sortOrder = SortDescriptor<CheckInTemplate>(\.sortOrder)
        _templates = Query(filter: #Predicate<CheckInTemplate> { $0.isActive }, sort: [sortOrder])
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                dateHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Divider()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)

                textEditor
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)

                actionBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .background(Color("backgroundPrimary"))
            .onAppear(perform: loadTodayEntry)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isViewMode.toggle()
                            if !isViewMode {
                                isTextEditorFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: isViewMode ? "square.and.pencil" : "eye")
                            .foregroundStyle(Color("accentBright"))
                    }
                }
            }
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(today.formatted(.dateTime.weekday(.wide)))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color("textPrimary"))

                Text(today.formatted(.dateTime.month(.wide).day().year()))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("textSecondary"))
            }

            Spacer()

            Image(systemName: syncService.isSyncing ? "arrow.triangle.2.circlepath.icloud" : (syncService.lastError != nil ? "exclamationmark.icloud" : "checkmark.icloud"))
                .font(.system(.body))
                .foregroundStyle(syncService.lastError != nil ? .red : Color("textSecondary"))
                .symbolEffect(.pulse, isActive: syncService.isSyncing)

            if showSavedIndicator {
                Text("Saved")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("textSecondary"))
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Text Area

    private var textEditor: some View {
        Group {
            if isViewMode {
                ScrollView {
                    MarkdownTextView(text: diaryText)
                        .padding(.top, 8)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isViewMode = false
                        isTextEditorFocused = true
                    }
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if diaryText.isEmpty {
                        Text("What's on your mind today?")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(Color("textSecondary").opacity(0.6))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $diaryText)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color("textPrimary"))
                        .scrollContentBackground(.hidden)
                        .focused($isTextEditorFocused)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: diaryText) { _, newValue in
                            debounceSave(text: newValue)
                        }
                        .onAppear {
                            if !isViewMode {
                                isTextEditorFocused = true
                            }
                        }
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                showLocationEditor = true
            } label: {
                Label(
                    entry?.locationText ?? "Add location",
                    systemImage: "mappin"
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color("textSecondary"))
            }
            .sheet(isPresented: $showLocationEditor) {
                LocationEditSheet(entry: entry)
            }

            Spacer()

            Button {
                showPhotoPicker = true
            } label: {
                Label(
                    "\(entry?.safePhotoAssets.count ?? 0)",
                    systemImage: "photo"
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color("textSecondary"))
            }

            if let entry {
                let total = templates.count
                let completed = entry.completedCheckIns
                NavigationLink {
                    EntryDetailView(monthDayKey: todayKey, year: todayYear, scrollToCheckIns: true)
                } label: {
                    Label(
                        "\(completed)/\(total)",
                        systemImage: "checkmark.circle"
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(completed == total && total > 0
                        ? Color("habitComplete")
                        : Color("textSecondary"))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Data

    private func loadTodayEntry() {
        let key = todayKey
        let year = todayYear
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == year }
        )
        entry = try? modelContext.fetch(descriptor).first
        diaryText = entry?.diaryText ?? ""
    }

    private func debounceSave(text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveEntry(text: text)
            }
        }
    }

    private func saveEntry(text: String) {
        if let entry {
            entry.diaryText = text
            entry.updatedAt = .now
            entry.syncStatus = SyncStatus.pending
        } else {
            let newEntry = DiaryEntry(
                monthDayKey: todayKey,
                year: todayYear,
                date: today,
                weekday: DiaryEntry.weekdayName(from: today)
            )
            newEntry.diaryText = text
            modelContext.insert(newEntry)
            self.entry = newEntry
        }

        do {
            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.3)) {
                showSavedIndicator = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSavedIndicator = false
                    }
                }
            }
            syncService.scheduleDebouncedSync()
        } catch {
            print("[ForeverDiary] Home save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Location Edit Sheet

private struct LocationEditSheet: View {
    let entry: DiaryEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var locationText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("City or place name", text: $locationText)
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry?.locationText = locationText.isEmpty ? nil : locationText
                        dismiss()
                    }
                }
            }
            .onAppear {
                locationText = entry?.locationText ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text("Nothing written yet.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color("textSecondary").opacity(0.6))
        } else {
            Text(renderedMarkdown)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color("textPrimary"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var renderedMarkdown: AttributedString {
        let processed = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    return "\u{2022} " + String(trimmed.dropFirst(2))
                }
                if trimmed.hasPrefix("* ") {
                    return "\u{2022} " + String(trimmed.dropFirst(2))
                }
                return String(line)
            }
            .joined(separator: "\n")

        do {
            return try AttributedString(
                markdown: processed,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }
}
