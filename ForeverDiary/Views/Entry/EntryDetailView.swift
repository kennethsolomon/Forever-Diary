import SwiftUI
import SwiftData
import PhotosUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService

    let monthDayKey: String
    let year: Int
    var scrollToCheckIns: Bool = false

    @State private var entry: DiaryEntry?
    @State private var diaryText = ""
    @State private var locationText = ""
    @State private var isCheckInsExpanded = true
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoToDelete: PhotoAsset?
    @State private var showDeletePhotoAlert = false
    @State private var showPhotoLimitAlert = false
    @State private var galleryStartIndex: Int?
    @State private var saveTask: Task<Void, Never>?
    @State private var locationSaveTask: Task<Void, Never>?
    @State private var showSaved = false

    @Query private var templates: [CheckInTemplate]

    init(monthDayKey: String, year: Int, scrollToCheckIns: Bool = false) {
        self.monthDayKey = monthDayKey
        self.year = year
        self.scrollToCheckIns = scrollToCheckIns
        let sortOrder = SortDescriptor<CheckInTemplate>(\.sortOrder)
        _templates = Query(filter: #Predicate<CheckInTemplate> { $0.isActive }, sort: [sortOrder])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    diarySection
                    checkInSection
                        .id("checkIns")
                    photoSection
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                loadEntry()
                if scrollToCheckIns {
                    Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        withAnimation { proxy.scrollTo("checkIns", anchor: .top) }
                    }
                }
            }
        }
        .background(Color("backgroundPrimary"))
        .navigationTitle(formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(
            get: { galleryStartIndex != nil },
            set: { if !$0 { galleryStartIndex = nil } }
        )) {
            PhotoGalleryView(photos: sortedPhotos, startIndex: galleryStartIndex ?? 0)
        }
        .alert("Delete Photo?", isPresented: $showDeletePhotoAlert) {
            Button("Delete", role: .destructive) {
                if let photoToDelete {
                    let context = modelContext
                    let photo = photoToDelete
                    Task {
                        await syncService.deletePhoto(photo, context: context)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Photo Limit", isPresented: $showPhotoLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Maximum \(PhotoAsset.maxPhotosPerEntry) photos per entry.")
        }
    }

    private var sortedPhotos: [PhotoAsset] {
        entry?.safePhotoAssets.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
    }

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

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry?.weekday ?? "")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("textPrimary"))
                Spacer()
                Text(String(year))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Color("textSecondary"))
                if showSaved {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(Color("textSecondary"))
                        .transition(.opacity)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.caption)
                    .foregroundStyle(Color("textSecondary"))
                TextField("Add location", text: $locationText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                    .onSubmit { saveLocation() }
                    .onChange(of: locationText) { _, _ in debounceLocationSave() }
            }
        }
    }

    // MARK: - Diary Text

    private var diarySection: some View {
        ZStack(alignment: .topLeading) {
            if diaryText.isEmpty {
                Text("Write about your day...")
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
                .frame(minHeight: 200)
                .onChange(of: diaryText) { _, newValue in
                    debounceSave(text: newValue)
                }
        }
    }

    // MARK: - Check-ins

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCheckInsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isCheckInsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Daily Check-in")
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    if let entry {
                        Text("\(entry.completedCheckIns)/\(templates.count)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color("textSecondary"))
                    }
                }
                .foregroundStyle(Color("textPrimary"))
            }

            if isCheckInsExpanded {
                VStack(spacing: 12) {
                    ForEach(templates) { template in
                        checkInRow(for: template)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("surfaceCard"))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func checkInRow(for template: CheckInTemplate) -> some View {
        let value = checkInValue(for: template)
        HStack {
            Text(template.label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color("textPrimary"))
                .frame(width: 100, alignment: .leading)

            Spacer()

            switch template.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { value?.boolValue ?? false },
                    set: { newVal in updateCheckIn(template: template, bool: newVal) }
                ))
                .labelsHidden()
                .tint(Color("habitComplete"))

            case .text:
                TextField("...", text: Binding(
                    get: { value?.textValue ?? "" },
                    set: { newVal in updateCheckIn(template: template, text: newVal) }
                ))
                .font(.system(.subheadline, design: .rounded))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)

            case .number:
                TextField("0", value: Binding(
                    get: { value?.numberValue ?? 0 },
                    set: { newVal in updateCheckIn(template: template, number: newVal) }
                ), format: .number)
                .font(.system(.subheadline, design: .rounded))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 80)
            }
        }
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))

                if let entry {
                    Text("(\(entry.safePhotoAssets.count))")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }

                Spacer()

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: max(0, PhotoAsset.maxPhotosPerEntry - (entry?.safePhotoAssets.count ?? 0)),
                    matching: .images
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color("accentBright"))
                }
                .onChange(of: selectedPhotos) { _, items in
                    Task { await addPhotos(from: items) }
                    selectedPhotos = []
                }
            }

            if !sortedPhotos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(sortedPhotos.enumerated()), id: \.element.id) { index, photo in
                        if let uiImage = UIImage(data: photo.thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    galleryStartIndex = index
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        photoToDelete = photo
                                        showDeletePhotoAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Operations

    private func loadEntry() {
        let key = monthDayKey
        let yr = year
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr && $0.deletedAt == nil }
        )
        entry = try? modelContext.fetch(descriptor).first
        diaryText = entry?.diaryText ?? ""
        locationText = entry?.locationText ?? ""
    }

    private func ensureEntry() -> DiaryEntry {
        if let entry { return entry }
        let parts = monthDayKey.split(separator: "-")
        var components = DateComponents()
        components.month = Int(parts[0])
        components.day = Int(parts[1])
        components.year = year
        let date = Calendar.current.date(from: components) ?? .now

        // Remove any pending tombstone before inserting to avoid duplicate sk in pushPending.
        let key = monthDayKey
        let yr = year
        let tombstoneDescriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.monthDayKey == key && $0.year == yr }
        )
        if let tombstone = try? modelContext.fetch(tombstoneDescriptor).first {
            modelContext.delete(tombstone)
        }

        let newEntry = DiaryEntry(
            monthDayKey: monthDayKey,
            year: year,
            date: date,
            weekday: DiaryEntry.weekdayName(from: date)
        )
        modelContext.insert(newEntry)
        do {
            try modelContext.save()
        } catch {
            print("[ForeverDiary] Entry creation save failed: \(error.localizedDescription)")
        }
        self.entry = newEntry
        return newEntry
    }

    private func debounceSave(text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let e = ensureEntry()
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
                    print("[ForeverDiary] Diary save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func debounceLocationSave() {
        locationSaveTask?.cancel()
        locationSaveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            await MainActor.run { saveLocation() }
        }
    }

    private func saveLocation() {
        guard let entry else { return }
        entry.locationText = locationText.isEmpty ? nil : locationText
        entry.updatedAt = .now
        entry.syncStatus = SyncStatus.pending
        do {
            try modelContext.save()
            syncService.scheduleDebouncedSync()
        } catch {
            print("[ForeverDiary] Location save failed: \(error.localizedDescription)")
        }
    }

    private func checkInValue(for template: CheckInTemplate) -> CheckInValue? {
        entry?.safeCheckInValues.first { $0.templateId == template.id }
    }

    private func updateCheckIn(template: CheckInTemplate, bool: Bool? = nil, text: String? = nil, number: Double? = nil) {
        let e = ensureEntry()
        if let existing = e.safeCheckInValues.first(where: { $0.templateId == template.id }) {
            existing.boolValue = bool ?? existing.boolValue
            existing.textValue = text ?? existing.textValue
            existing.numberValue = number ?? existing.numberValue
        } else {
            let value = CheckInValue(templateId: template.id, boolValue: bool, textValue: text, numberValue: number)
            value.entry = e
            modelContext.insert(value)
        }
        e.updatedAt = .now
        e.syncStatus = SyncStatus.pending
        try? modelContext.save()
        syncService.scheduleDebouncedSync()
    }

    // MARK: - Image Helpers

    private func addPhotos(from items: [PhotosPickerItem]) async {
        let e = ensureEntry()
        for item in items {
            guard e.safePhotoAssets.count < PhotoAsset.maxPhotosPerEntry else {
                await MainActor.run { showPhotoLimitAlert = true }
                break
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let uiImage = UIImage(data: data) else { continue }

            let normalized = uiImage.normalizedOrientation()
            let resized = normalized.resizedIfNeeded(maxDimension: 4096)
            let compressed = resized.jpegData(compressionQuality: 0.85) ?? data
            guard compressed.count <= PhotoAsset.maxPhotoBytes else { continue }

            let thumbnailSize = CGSize(width: 300, height: 300)
            let thumbnail = resized.preparingThumbnail(of: thumbnailSize)
            let thumbData = thumbnail?.jpegData(compressionQuality: 0.8) ?? compressed

            let asset = PhotoAsset(imageData: compressed, thumbnailData: thumbData)
            asset.entry = e
            await MainActor.run {
                modelContext.insert(asset)
            }
        }
        await MainActor.run {
            e.updatedAt = .now
            try? modelContext.save()
        }
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    /// Returns a copy of the image drawn with .up orientation so EXIF rotation is baked in.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Downscales the image if its longest side exceeds `maxDimension`. Preserves aspect ratio.
    func resizedIfNeeded(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

