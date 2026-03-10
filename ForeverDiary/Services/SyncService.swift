import Foundation
import SwiftData

enum SyncStatus {
    static let pending = "pending"
    static let synced = "synced"
}

@Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    private let apiClient: APIClient
    private let authService: CognitoAuthService
    private let container: ModelContainer

    private let lastSyncKey = "lastSyncTimestamp"
    private var syncDebounceTask: Task<Void, Never>?

    private static let isoFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    init(apiClient: APIClient, authService: CognitoAuthService, container: ModelContainer) {
        self.apiClient = apiClient
        self.authService = authService
        self.container = container
        self.lastSyncDate = loadLastSyncDate()
    }

    /// Schedule a sync after a 5-second debounce delay.
    func scheduleDebouncedSync() {
        syncDebounceTask?.cancel()
        syncDebounceTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await syncAll()
        }
    }

    /// Full sync: push pending, pull remote, sync photos.
    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        do {
            try await authService.refreshIfNeeded()
            try await pushPending()
            try await pullRemote()
            try await uploadPhotos()
            try await downloadPhotos()
            lastSyncDate = Date()
            saveLastSyncDate(lastSyncDate!)
        } catch {
            lastError = error.localizedDescription
            print("[SyncService] syncAll error: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    /// Push all pending entries, templates, and check-in values to the cloud.
    @MainActor
    func pushPending() async throws {
        let context = ModelContext(container)

        let pending = SyncStatus.pending
        let entryPredicate = #Predicate<DiaryEntry> { $0.syncStatus == pending }
        let pendingEntries = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: entryPredicate))

        let templatePredicate = #Predicate<CheckInTemplate> { $0.syncStatus == pending }
        let pendingTemplates = try context.fetch(FetchDescriptor<CheckInTemplate>(predicate: templatePredicate))

        var items: [[String: Any]] = []

        for entry in pendingEntries {
            let entryData: [String: Any] = [
                "monthDayKey": entry.monthDayKey,
                "year": entry.year,
                "date": entry.date.timeIntervalSince1970,
                "weekday": entry.weekday,
                "diaryText": entry.diaryText,
                "locationText": entry.locationText ?? "",
                "createdAt": entry.createdAt.timeIntervalSince1970
            ]
            items.append([
                "sk": "entry#\(entry.monthDayKey)#\(entry.year)",
                "data": entryData,
                "updatedAt": Self.isoFormatter.string(from: entry.updatedAt)
            ])

            for value in entry.safeCheckInValues {
                var valueData: [String: Any] = [
                    "id": value.id.uuidString,
                    "templateId": value.templateId.uuidString
                ]
                if let b = value.boolValue { valueData["boolValue"] = b }
                if let t = value.textValue { valueData["textValue"] = t }
                if let n = value.numberValue { valueData["numberValue"] = n }

                items.append([
                    "sk": "checkin#\(entry.monthDayKey)#\(entry.year)#\(value.id.uuidString)",
                    "data": valueData,
                    "updatedAt": Self.isoFormatter.string(from: entry.updatedAt)
                ])
            }
        }

        for template in pendingTemplates {
            let templateData: [String: Any] = [
                "id": template.id.uuidString,
                "label": template.label,
                "type": template.type.rawValue,
                "isActive": template.isActive,
                "sortOrder": template.sortOrder
            ]
            items.append([
                "sk": "template#\(template.id.uuidString)",
                "data": templateData,
                "updatedAt": Self.isoFormatter.string(from: Date())
            ])
        }

        guard !items.isEmpty else { return }

        let batchSize = 25
        for i in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[i..<min(i + batchSize, items.count)])
            _ = try await apiClient.post(path: "/sync", body: ["items": batch])
        }

        let now = Date()
        for entry in pendingEntries {
            entry.syncStatus = SyncStatus.synced
            entry.lastSyncedAt = now
            for value in entry.safeCheckInValues {
                value.syncStatus = SyncStatus.synced
                value.lastSyncedAt = now
            }
        }
        for template in pendingTemplates {
            template.syncStatus = SyncStatus.synced
            template.lastSyncedAt = now
        }

        try context.save()
        print("[SyncService] Pushed \(items.count) items")
    }

    /// Pull remote changes since last sync.
    @MainActor
    func pullRemote() async throws {
        let context = ModelContext(container)

        var queryItems: [URLQueryItem] = []
        if let lastSync = loadLastSyncDate() {
            queryItems.append(URLQueryItem(name: "since", value: Self.isoFormatter.string(from: lastSync)))
        }

        let result = try await apiClient.get(path: "/sync", queryItems: queryItems)
        guard let remoteItems = result["items"] as? [[String: Any]] else { return }

        // Process entries and templates first so check-ins and photos can find their parents
        let sorted = remoteItems.sorted { a, b in
            let skA = (a["sk"] as? String) ?? ""
            let skB = (b["sk"] as? String) ?? ""
            let orderA = skA.hasPrefix("entry#") ? 0 : (skA.hasPrefix("template#") ? 1 : 2)
            let orderB = skB.hasPrefix("entry#") ? 0 : (skB.hasPrefix("template#") ? 1 : 2)
            return orderA < orderB
        }

        for item in sorted {
            guard let sk = item["sk"] as? String else { continue }

            if sk.hasPrefix("entry#") {
                try upsertEntry(item, sk: sk, context: context)
            } else if sk.hasPrefix("template#") {
                try upsertTemplate(item, context: context)
            } else if sk.hasPrefix("checkin#") {
                try upsertCheckInValue(item, sk: sk, context: context)
            } else if sk.hasPrefix("photo#") {
                try upsertPhoto(item, context: context)
            }
        }

        try context.save()
        print("[SyncService] Pulled \(remoteItems.count) items")
    }

    /// Upload pending photos to S3 and push metadata to DynamoDB.
    @MainActor
    func uploadPhotos() async throws {
        let context = ModelContext(container)
        let pending = SyncStatus.pending
        let predicate = #Predicate<PhotoAsset> { $0.syncStatus == pending }
        let pendingPhotos = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate))

        var metadataItems: [[String: Any]] = []

        for photo in pendingPhotos {
            let photoKey = "photos/\(photo.id.uuidString).jpg"
            let thumbKey = "photos/\(photo.id.uuidString)_thumb.jpg"

            let photoPresign = try await apiClient.post(path: "/presign", body: [
                "key": photoKey,
                "operation": "upload"
            ])
            let thumbPresign = try await apiClient.post(path: "/presign", body: [
                "key": thumbKey,
                "operation": "upload"
            ])

            guard let photoURL = photoPresign["url"] as? String,
                  let thumbURL = thumbPresign["url"] as? String else {
                continue
            }

            try await apiClient.uploadToPresignedURL(photoURL, data: photo.imageData)
            try await apiClient.uploadToPresignedURL(thumbURL, data: photo.thumbnailData)

            photo.s3Key = photoKey
            photo.s3ThumbKey = thumbKey
            photo.syncStatus = SyncStatus.synced
            photo.lastSyncedAt = Date()

            if let entry = photo.entry {
                let photoData: [String: Any] = [
                    "id": photo.id.uuidString,
                    "entryMonthDayKey": entry.monthDayKey,
                    "entryYear": entry.year,
                    "s3Key": photoKey,
                    "s3ThumbKey": thumbKey,
                    "createdAt": photo.createdAt.timeIntervalSince1970
                ]
                metadataItems.append([
                    "sk": "photo#\(photo.id.uuidString)",
                    "data": photoData,
                    "updatedAt": Self.isoFormatter.string(from: Date())
                ])
            }
        }

        if !metadataItems.isEmpty {
            let batchSize = 25
            for i in stride(from: 0, to: metadataItems.count, by: batchSize) {
                let batch = Array(metadataItems[i..<min(i + batchSize, metadataItems.count)])
                _ = try await apiClient.post(path: "/sync", body: ["items": batch])
            }
        }

        try context.save()
        if !pendingPhotos.isEmpty {
            print("[SyncService] Uploaded \(pendingPhotos.count) photos with metadata")
        }
    }

    /// Download photos that have S3 keys but no local data.
    @MainActor
    func downloadPhotos() async throws {
        let context = ModelContext(container)
        let predicate = #Predicate<PhotoAsset> { $0.s3Key != nil }
        let missingPhotos = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate)).filter { $0.imageData.isEmpty }

        for photo in missingPhotos {
            guard let photoKey = photo.s3Key else { continue }

            let photoPresign = try await apiClient.post(path: "/presign", body: [
                "key": photoKey,
                "operation": "download"
            ])
            if let photoURL = photoPresign["url"] as? String {
                photo.imageData = try await apiClient.downloadFromPresignedURL(photoURL)
            }

            if let thumbKey = photo.s3ThumbKey {
                let thumbPresign = try await apiClient.post(path: "/presign", body: [
                    "key": thumbKey,
                    "operation": "download"
                ])
                if let thumbURL = thumbPresign["url"] as? String {
                    photo.thumbnailData = try await apiClient.downloadFromPresignedURL(thumbURL)
                }
            }
        }

        try context.save()
        if !missingPhotos.isEmpty {
            print("[SyncService] Downloaded \(missingPhotos.count) photos")
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func upsertEntry(_ item: [String: Any], sk: String, context: ModelContext) throws {
        let parts = sk.split(separator: "#")
        guard parts.count >= 3,
              let monthDayKey = parts.dropFirst().first.map(String.init),
              let year = Int(parts.last ?? "") else { return }

        let remoteUpdatedAt = (item["updatedAt"] as? String).flatMap { Self.isoFormatter.date(from: $0) } ?? Date.distantPast

        let predicate = #Predicate<DiaryEntry> { $0.monthDayKey == monthDayKey && $0.year == year }
        let existing = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: predicate))

        if let local = existing.first {
            if remoteUpdatedAt > local.updatedAt {
                local.diaryText = item["diaryText"] as? String ?? local.diaryText
                local.locationText = item["locationText"] as? String
                local.weekday = item["weekday"] as? String ?? local.weekday
                local.updatedAt = remoteUpdatedAt
                local.syncStatus = SyncStatus.synced
                local.lastSyncedAt = Date()
            }
        } else {
            let date = (item["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let entry = DiaryEntry(
                monthDayKey: monthDayKey,
                year: year,
                date: date,
                weekday: item["weekday"] as? String ?? "",
                diaryText: item["diaryText"] as? String ?? "",
                locationText: item["locationText"] as? String
            )
            entry.syncStatus = SyncStatus.synced
            entry.lastSyncedAt = Date()
            if let createdAt = (item["createdAt"] as? Double).map({ Date(timeIntervalSince1970: $0) }) {
                entry.createdAt = createdAt
            }
            entry.updatedAt = remoteUpdatedAt
            context.insert(entry)
        }
    }

    @MainActor
    private func upsertTemplate(_ item: [String: Any], context: ModelContext) throws {
        guard let idString = item["id"] as? String,
              let id = UUID(uuidString: idString) else { return }

        let predicate = #Predicate<CheckInTemplate> { $0.id == id }
        let existing = try context.fetch(FetchDescriptor<CheckInTemplate>(predicate: predicate))

        if let local = existing.first {
            local.label = item["label"] as? String ?? local.label
            if let typeRaw = item["type"] as? String, let type = CheckInFieldType(rawValue: typeRaw) {
                local.type = type
            }
            local.isActive = item["isActive"] as? Bool ?? local.isActive
            local.sortOrder = item["sortOrder"] as? Int ?? local.sortOrder
            local.syncStatus = SyncStatus.synced
            local.lastSyncedAt = Date()
        } else {
            let template = CheckInTemplate(
                id: id,
                label: item["label"] as? String ?? "",
                type: CheckInFieldType(rawValue: item["type"] as? String ?? "text") ?? .text,
                isActive: item["isActive"] as? Bool ?? true,
                sortOrder: item["sortOrder"] as? Int ?? 0
            )
            template.syncStatus = SyncStatus.synced
            template.lastSyncedAt = Date()
            context.insert(template)
        }
    }

    @MainActor
    private func upsertCheckInValue(_ item: [String: Any], sk: String, context: ModelContext) throws {
        // Parse sk: "checkin#MM-DD#YYYY#UUID"
        let parts = sk.split(separator: "#")
        guard parts.count >= 4,
              let monthDayKey = parts.dropFirst().first.map(String.init),
              let year = Int(parts[2]),
              let valueIdString = parts.last.map(String.init),
              let valueId = UUID(uuidString: valueIdString) else { return }

        let entryPredicate = #Predicate<DiaryEntry> { $0.monthDayKey == monthDayKey && $0.year == year }
        guard let entry = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: entryPredicate)).first else { return }

        let existingPredicate = #Predicate<CheckInValue> { $0.id == valueId }
        let existing = try context.fetch(FetchDescriptor<CheckInValue>(predicate: existingPredicate))

        if let local = existing.first {
            if let tidStr = item["templateId"] as? String, let tid = UUID(uuidString: tidStr) {
                local.templateId = tid
            }
            if let b = item["boolValue"] as? Bool { local.boolValue = b }
            if let t = item["textValue"] as? String { local.textValue = t }
            if let n = item["numberValue"] as? Double { local.numberValue = n }
            local.syncStatus = SyncStatus.synced
            local.lastSyncedAt = Date()
        } else {
            let templateId = (item["templateId"] as? String).flatMap(UUID.init) ?? UUID()
            let value = CheckInValue(
                id: valueId,
                templateId: templateId,
                boolValue: item["boolValue"] as? Bool,
                textValue: item["textValue"] as? String,
                numberValue: item["numberValue"] as? Double
            )
            value.entry = entry
            value.syncStatus = SyncStatus.synced
            value.lastSyncedAt = Date()
            context.insert(value)
        }
    }

    @MainActor
    private func upsertPhoto(_ item: [String: Any], context: ModelContext) throws {
        guard let idString = item["id"] as? String,
              let id = UUID(uuidString: idString),
              let s3Key = item["s3Key"] as? String,
              let entryMonthDayKey = item["entryMonthDayKey"] as? String,
              let entryYear = item["entryYear"] as? Int else { return }

        let predicate = #Predicate<PhotoAsset> { $0.id == id }
        if let existing = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate)).first {
            if existing.s3Key == nil {
                existing.s3Key = s3Key
                existing.s3ThumbKey = item["s3ThumbKey"] as? String
            }
            return
        }

        let entryPredicate = #Predicate<DiaryEntry> { $0.monthDayKey == entryMonthDayKey && $0.year == entryYear }
        guard let entry = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: entryPredicate)).first else { return }

        // Stub photo — downloadPhotos() fills in the binary data
        let photo = PhotoAsset(id: id, imageData: Data(), thumbnailData: Data())
        photo.s3Key = s3Key
        photo.s3ThumbKey = item["s3ThumbKey"] as? String
        if let createdAt = (item["createdAt"] as? Double).map({ Date(timeIntervalSince1970: $0) }) {
            photo.createdAt = createdAt
        }
        photo.entry = entry
        photo.syncStatus = SyncStatus.synced
        photo.lastSyncedAt = Date()
        context.insert(photo)
    }

    private func loadLastSyncDate() -> Date? {
        guard let timestamp = UserDefaults.standard.string(forKey: lastSyncKey) else { return nil }
        return Self.isoFormatter.date(from: timestamp)
    }

    private func saveLastSyncDate(_ date: Date) {
        UserDefaults.standard.set(Self.isoFormatter.string(from: date), forKey: lastSyncKey)
    }
}
