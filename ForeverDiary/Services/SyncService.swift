import Foundation
import SwiftData

@Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    private let apiClient: APIClient
    private let authService: CognitoAuthService
    private let container: ModelContainer

    private let lastSyncKey = "lastSyncTimestamp"

    init(apiClient: APIClient, authService: CognitoAuthService, container: ModelContainer) {
        self.apiClient = apiClient
        self.authService = authService
        self.container = container
        self.lastSyncDate = loadLastSyncDate()
    }

    /// Full sync: push pending, then pull remote changes.
    /// On first launch (empty local DB but existing Keychain identity), does a full pull.
    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        do {
            try await authService.refreshIfNeeded()

            // First-launch detection: if Keychain has identity but local DB is empty, do full pull
            let isFirstLaunch = await checkFirstLaunch()
            if isFirstLaunch {
                print("[SyncService] First launch detected — pulling all remote data")
            }

            try await pushPending()
            try await pullRemote()
            if isFirstLaunch {
                try await downloadPhotos()
            }
            try await uploadPhotos()
            lastSyncDate = Date()
            saveLastSyncDate(lastSyncDate!)
        } catch {
            lastError = error.localizedDescription
            print("[SyncService] syncAll error: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    @MainActor
    private func checkFirstLaunch() -> Bool {
        guard authService.identityId != nil else { return false }
        guard loadLastSyncDate() == nil else { return false }
        let context = ModelContext(container)
        let count = (try? context.fetchCount(FetchDescriptor<DiaryEntry>())) ?? 0
        return count == 0
    }

    /// Push all pending entries, templates, and check-in values to the cloud.
    @MainActor
    func pushPending() async throws {
        let context = ModelContext(container)

        // Fetch pending diary entries
        let entryPredicate = #Predicate<DiaryEntry> { $0.syncStatus == "pending" }
        let pendingEntries = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: entryPredicate))

        // Fetch pending templates
        let templatePredicate = #Predicate<CheckInTemplate> { $0.syncStatus == "pending" }
        let pendingTemplates = try context.fetch(FetchDescriptor<CheckInTemplate>(predicate: templatePredicate))

        var items: [[String: Any]] = []

        // Serialize entries
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
                "updatedAt": ISO8601DateFormatter().string(from: entry.updatedAt)
            ])

            // Serialize check-in values for this entry
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
                    "updatedAt": ISO8601DateFormatter().string(from: entry.updatedAt)
                ])
            }
        }

        // Serialize templates
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
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ])
        }

        guard !items.isEmpty else { return }

        // Push in batches of 25
        let batchSize = 25
        for i in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[i..<min(i + batchSize, items.count)])
            _ = try await apiClient.post(path: "/sync", body: ["items": batch])
        }

        // Mark as synced
        let now = Date()
        for entry in pendingEntries {
            entry.syncStatus = "synced"
            entry.lastSyncedAt = now
            for value in entry.safeCheckInValues {
                value.syncStatus = "synced"
                value.lastSyncedAt = now
            }
        }
        for template in pendingTemplates {
            template.syncStatus = "synced"
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
            queryItems.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: lastSync)))
        }

        let result = try await apiClient.get(path: "/sync", queryItems: queryItems)
        guard let remoteItems = result["items"] as? [[String: Any]] else { return }

        for item in remoteItems {
            guard let sk = item["sk"] as? String else { continue }

            if sk.hasPrefix("entry#") {
                try upsertEntry(item, sk: sk, context: context)
            } else if sk.hasPrefix("template#") {
                try upsertTemplate(item, context: context)
            }
            // check-in values are handled as part of entry pull
        }

        try context.save()
        print("[SyncService] Pulled \(remoteItems.count) items")
    }

    /// Upload pending photos to S3 via presigned URLs.
    @MainActor
    func uploadPhotos() async throws {
        let context = ModelContext(container)
        let predicate = #Predicate<PhotoAsset> { $0.syncStatus == "pending" }
        let pendingPhotos = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate))

        for photo in pendingPhotos {
            let photoKey = "photos/\(photo.id.uuidString).jpg"
            let thumbKey = "photos/\(photo.id.uuidString)_thumb.jpg"

            // Get presigned upload URLs
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

            // Upload files
            try await apiClient.uploadToPresignedURL(photoURL, data: photo.imageData)
            try await apiClient.uploadToPresignedURL(thumbURL, data: photo.thumbnailData)

            // Update model
            photo.s3Key = photoKey
            photo.s3ThumbKey = thumbKey
            photo.syncStatus = "synced"
            photo.lastSyncedAt = Date()
        }

        try context.save()
        if !pendingPhotos.isEmpty {
            print("[SyncService] Uploaded \(pendingPhotos.count) photos")
        }
    }

    /// Download photos that have S3 keys but no local data.
    @MainActor
    func downloadPhotos() async throws {
        let context = ModelContext(container)
        let predicate = #Predicate<PhotoAsset> { $0.s3Key != nil && $0.imageData.isEmpty }
        let missingPhotos = try context.fetch(FetchDescriptor<PhotoAsset>(predicate: predicate))

        for photo in missingPhotos {
            guard let photoKey = photo.s3Key else { continue }

            // Download full image
            let photoPresign = try await apiClient.post(path: "/presign", body: [
                "key": photoKey,
                "operation": "download"
            ])
            if let photoURL = photoPresign["url"] as? String {
                photo.imageData = try await apiClient.downloadFromPresignedURL(photoURL)
            }

            // Download thumbnail
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
        // Parse sk: "entry#MM-DD#YYYY"
        let parts = sk.split(separator: "#")
        guard parts.count >= 3,
              let monthDayKey = parts.dropFirst().first.map(String.init),
              let year = Int(parts.last ?? "") else { return }

        let remoteUpdatedAt = (item["updatedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast

        // Check if entry already exists
        let predicate = #Predicate<DiaryEntry> { $0.monthDayKey == monthDayKey && $0.year == year }
        let existing = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: predicate))

        if let local = existing.first {
            // Last-write-wins
            if remoteUpdatedAt > local.updatedAt {
                local.diaryText = item["diaryText"] as? String ?? local.diaryText
                local.locationText = item["locationText"] as? String
                local.weekday = item["weekday"] as? String ?? local.weekday
                local.updatedAt = remoteUpdatedAt
                local.syncStatus = "synced"
                local.lastSyncedAt = Date()
            }
        } else {
            // Create new entry from remote
            let date = (item["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let entry = DiaryEntry(
                monthDayKey: monthDayKey,
                year: year,
                date: date,
                weekday: item["weekday"] as? String ?? "",
                diaryText: item["diaryText"] as? String ?? "",
                locationText: item["locationText"] as? String
            )
            entry.syncStatus = "synced"
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
            local.syncStatus = "synced"
            local.lastSyncedAt = Date()
        } else {
            let template = CheckInTemplate(
                id: id,
                label: item["label"] as? String ?? "",
                type: CheckInFieldType(rawValue: item["type"] as? String ?? "text") ?? .text,
                isActive: item["isActive"] as? Bool ?? true,
                sortOrder: item["sortOrder"] as? Int ?? 0
            )
            template.syncStatus = "synced"
            template.lastSyncedAt = Date()
            context.insert(template)
        }
    }

    private func loadLastSyncDate() -> Date? {
        guard let timestamp = UserDefaults.standard.string(forKey: lastSyncKey) else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
    }

    private func saveLastSyncDate(_ date: Date) {
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: date), forKey: lastSyncKey)
    }
}
