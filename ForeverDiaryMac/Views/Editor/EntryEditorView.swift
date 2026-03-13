import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EntryEditorView: View {
    let monthDayKey: String
    let year: Int
    let entry: DiaryEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(SpeechService.self) private var speechService
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var diaryText = ""
    @State private var locationText = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showSaved = false
    @State private var isCheckInsExpanded = true

    // Speech
    @State private var showRecording = false

    // Photos
    @State private var showPhotoLimitAlert = false
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    @State private var photoToDelete: PhotoAsset?
    @State private var showDeletePhotoAlert = false

    @Query private var templates: [CheckInTemplate]

    init(monthDayKey: String, year: Int, entry: DiaryEntry?) {
        self.monthDayKey = monthDayKey
        self.year = year
        self.entry = entry
        let sortOrder = SortDescriptor<CheckInTemplate>(\.sortOrder)
        _templates = Query(filter: #Predicate<CheckInTemplate> { $0.isActive }, sort: [sortOrder])
    }

    private var sortedPhotos: [PhotoAsset] {
        (entry?.safePhotoAssets ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    if syncService.showRemoteUpdateToast {
                        remoteUpdateToast
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Location
                    HStack(spacing: 8) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12))
                            .foregroundStyle(Color("textSecondary"))
                        TextField("Add location", text: $locationText)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color("textSecondary"))
                            .textFieldStyle(.plain)
                            .onSubmit { saveLocation() }
                            .onChange(of: locationText) { _, _ in debounceLocationSave() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color("surfaceCard"))
                    )

                    // Diary text
                    ZStack(alignment: .topLeading) {
                        if diaryText.isEmpty {
                            Text("What's on your mind today?")
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(Color("textSecondary").opacity(0.5))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $diaryText)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(Color("textPrimary"))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 250)
                            .onChange(of: diaryText) { _, newValue in debounceSave(text: newValue) }
                    }

                    // Check-ins section
                    if let entry {
                        checkInSection(entry: entry)
                    }

                    // Photos section
                    if let entry {
                        photosSection(entry: entry)
                    }
                }
                .padding(24)
            }

            Divider()
            actionBar
        }
        .background(Color("backgroundPrimary"))
        .navigationTitle(formattedDate)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SyncStatusView(
                    isSyncing: syncService.isSyncing,
                    hasError: syncService.lastError != nil,
                    isConnected: networkMonitor.isConnected
                )
            }
        }
        .onAppear {
            diaryText = entry?.diaryText ?? ""
            locationText = entry?.locationText ?? ""
        }
        .onChange(of: entry?.diaryText) { _, newText in
            // Cancel any in-flight debounce so remote data takes priority
            saveTask?.cancel()
            saveTask = nil
            let incoming = newText ?? ""
            if incoming != diaryText { diaryText = incoming }
        }
        .onChange(of: entry?.locationText) { _, newLocation in
            locationText = newLocation ?? ""
        }
        .alert("Photo Limit", isPresented: $showPhotoLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can add up to \(PhotoAsset.maxPhotosPerEntry) photos per entry.")
        }
        .alert("Delete Photo?", isPresented: $showDeletePhotoAlert) {
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete {
                    Task { await syncService.deletePhoto(photo, context: modelContext) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showGallery) {
            MacPhotoGalleryView(photos: sortedPhotos, startIndex: galleryStartIndex)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry?.weekday ?? computedWeekday)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color("textPrimary"))
                Text("\(formattedDate), \(String(year))")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
            Spacer()
            if showSaved {
                Text("Saved")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Photos

    private func photosSection(entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))
                Spacer()
                let remaining = max(0, PhotoAsset.maxPhotosPerEntry - sortedPhotos.count)
                if remaining > 0 {
                    Button {
                        openFilePicker(entry: entry, remaining: remaining)
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color("accentBright"))
                    }
                    .buttonStyle(.plain)
                }
            }

            if sortedPhotos.isEmpty {
                Text("No photos yet")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary").opacity(0.6))
                    .italic()
            } else {
                let columns = [GridItem(.adaptive(minimum: 90, maximum: 90), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sortedPhotos) { photo in
                        photoCell(photo: photo)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("surfaceCard"))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }

    private func photoCell(photo: PhotoAsset) -> some View {
        let img = NSImage(data: photo.thumbnailData)
        return Group {
            if let img {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("surfaceCard"))
                    .frame(width: 90, height: 90)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(Color("textSecondary"))
                    }
            }
        }
        .onTapGesture {
            galleryStartIndex = sortedPhotos.firstIndex(where: { $0.id == photo.id }) ?? 0
            showGallery = true
        }
        .contextMenu {
            Button(role: .destructive) {
                photoToDelete = photo
                showDeletePhotoAlert = true
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
    }

    // MARK: - Check-ins

    private func checkInSection(entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCheckInsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isCheckInsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color("textSecondary"))
                    Text("Daily Check-in")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color("textPrimary"))
                    Spacer()
                    Text("\(entry.completedCheckIns)/\(templates.count)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }
            .buttonStyle(.plain)

            if isCheckInsExpanded {
                VStack(spacing: 10) {
                    ForEach(templates) { template in
                        checkInRow(for: template, entry: entry)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color("surfaceCard"))
                        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func checkInRow(for template: CheckInTemplate, entry: DiaryEntry) -> some View {
        let value = entry.safeCheckInValues.first(where: { $0.templateId == template.id })
        HStack {
            Text(template.label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color("textPrimary"))
                .frame(width: 110, alignment: .leading)

            Spacer()

            switch template.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { value?.boolValue ?? false },
                    set: { newVal in updateCheckIn(template: template, entry: entry, bool: newVal) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color("habitComplete"))
                .controlSize(.small)

            case .text:
                TextField("...", text: Binding(
                    get: { value?.textValue ?? "" },
                    set: { newVal in updateCheckIn(template: template, entry: entry, text: newVal) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

            case .number:
                TextField("0", value: Binding(
                    get: { value?.numberValue ?? 0 },
                    set: { newVal in updateCheckIn(template: template, entry: entry, number: newVal) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Dictate
            Button {
                showRecording = true
            } label: {
                Label("Dictate", systemImage: speechService.isRecording ? "mic.fill" : "mic")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(speechService.isRecording ? Color("accentBright") : Color("textSecondary"))
                    .symbolEffect(.variableColor.iterative, isActive: speechService.isRecording)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRecording) {
                RecordingView { text in
                    diaryText += (diaryText.isEmpty ? "" : " ") + text
                    debounceSave(text: diaryText)
                }
                .environment(speechService)
                .frame(minWidth: 320, minHeight: 280)
            }

            // Photo count
            Label(String(sortedPhotos.count), systemImage: "photo")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color("textSecondary"))

            Spacer()

            // Check-in progress
            if let entry {
                Label(
                    "\(entry.completedCheckIns)/\(templates.count)",
                    systemImage: "checkmark.circle"
                )
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(
                    entry.completedCheckIns == templates.count && templates.count > 0
                        ? Color("habitComplete") : Color("textSecondary")
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color("surfaceCard"))
    }

    // MARK: - Remote Update Toast

    private var remoteUpdateToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(Color("accentBright"))
                .symbolEffect(.pulse, options: .nonRepeating, isActive: syncService.showRemoteUpdateToast)
            Text("Updated from another device")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color("textSecondary"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("surfaceCard"))
                .stroke(Color("borderSubtle"), lineWidth: 0.5)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        )
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let parts = monthDayKey.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              month >= 1, month <= 12 else { return monthDayKey }
        let formatter = DateFormatter()
        let monthName = formatter.monthSymbols[month - 1]
        return "\(monthName) \(day)"
    }

    private var computedWeekday: String {
        var comps = DateComponents()
        let parts = monthDayKey.split(separator: "-")
        comps.month = Int(parts[0])
        comps.day = Int(parts.count > 1 ? parts[1] : "1")
        comps.year = year
        let date = Calendar.current.date(from: comps) ?? .now
        return DiaryEntry.weekdayName(from: date)
    }

    private func ensureEntry() -> DiaryEntry {
        if let entry { return entry }
        let parts = monthDayKey.split(separator: "-")
        var comps = DateComponents()
        comps.month = Int(parts[0])
        comps.day = Int(parts.count > 1 ? parts[1] : "1")
        comps.year = year
        let date = Calendar.current.date(from: comps) ?? .now

        let key = monthDayKey
        let yr = year
        let tombstoneDesc = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        if let tombstone = try? modelContext.fetch(tombstoneDesc).first {
            modelContext.delete(tombstone)
        }

        let newEntry = DiaryEntry(
            monthDayKey: monthDayKey,
            year: year,
            date: date,
            weekday: DiaryEntry.weekdayName(from: date)
        )
        modelContext.insert(newEntry)
        try? modelContext.save()
        return newEntry
    }

    private func debounceSave(text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let e = ensureEntry()
                guard text != e.diaryText else { saveTask = nil; return }
                e.diaryText = text
                e.updatedAt = .now
                e.syncStatus = SyncStatus.pending
                do {
                    try modelContext.save()
                    syncService.scheduleDebouncedSync()
                    withAnimation { showSaved = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        await MainActor.run { withAnimation { showSaved = false } }
                    }
                } catch {
                    print("[ForeverDiaryMac] Diary save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func debounceLocationSave() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run { saveLocation() }
        }
    }

    private func saveLocation() {
        guard let entry else { return }
        let newLocation = locationText.isEmpty ? nil : locationText
        guard newLocation != entry.locationText else { return }
        entry.locationText = newLocation
        entry.updatedAt = .now
        entry.syncStatus = SyncStatus.pending
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
    }

    private func openFilePicker(entry: DiaryEntry, remaining: Int) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = remaining > 1
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .webP]
        panel.message = "Choose photos to add to this entry"
        panel.prompt = "Add Photos"
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = Array(panel.urls.prefix(remaining))
            Task { await addPhotos(from: urls, entry: entry) }
        }
    }

    private func addPhotos(from urls: [URL], entry: DiaryEntry) async {
        let currentCount = entry.safePhotoAssets.count
        let remaining = PhotoAsset.maxPhotosPerEntry - currentCount
        guard remaining > 0 else {
            await MainActor.run { showPhotoLimitAlert = true }
            return
        }

        for url in Array(urls.prefix(remaining)) {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let compressed = MacImageHelper.compress(data, maxDimension: 4096, quality: 0.85) else { continue }
            guard compressed.count <= PhotoAsset.maxPhotoBytes else { continue }
            let thumbData = MacImageHelper.thumbnail(data, size: 300, quality: 0.8) ?? compressed

            await MainActor.run {
                let photo = PhotoAsset(imageData: compressed, thumbnailData: thumbData)
                photo.entry = entry
                modelContext.insert(photo)
                try? modelContext.save()
            }
        }

        await MainActor.run {
            syncService.scheduleDebouncedSync()
        }
    }

    private func updateCheckIn(template: CheckInTemplate, entry: DiaryEntry, bool: Bool? = nil, text: String? = nil, number: Double? = nil) {
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
