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
    private let networkMonitor: NetworkMonitor

    private let lastSyncKey = "lastSyncTimestamp"
    private var syncDebounceTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private static let isoFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    init(apiClient: APIClient, authService: CognitoAuthService, container: ModelContainer, networkMonitor: NetworkMonitor) {
        self.apiClient = apiClient
        self.authService = authService
        self.container = container
        self.networkMonitor = networkMonitor
        self.lastSyncDate = loadLastSyncDate()
    }

    /// Soft-delete an entry: mark as tombstone so pushPending can sync the deletion.
    /// Children are removed locally immediately; the entry itself is hard-deleted after the tombstone is pushed.
    @MainActor
    func deleteEntry(_ entry: DiaryEntry, context: ModelContext) async {
        let monthDayKey = entry.monthDayKey
        let year = entry.year
        let photos = entry.safePhotoAssets
        let checkIns = entry.safeCheckInValues

        // Collect child DynamoDB SKs and S3 keys before removing them locally
        var childDeleteItems: [[String: Any]] = checkIns.map { v in
            ["sk": "checkin#\(monthDayKey)#\(year)#\(v.id.uuidString)", "operation": "delete"]
        }
        for photo in photos {
            childDeleteItems.append(["sk": "photo#\(photo.id.uuidString)", "operation": "delete"])
        }
        let s3Keys: [String] = photos.flatMap { [$0.s3Key, $0.s3ThumbKey].compactMap { $0 } }

        // Remove children locally so they are invisible immediately
        for value in checkIns { context.delete(value) }
        for photo in photos { context.delete(photo) }

        // Soft-delete the entry — pushPending will send a tombstone then hard-delete it
        entry.deletedAt = .now
        entry.updatedAt = .now
        entry.syncStatus = SyncStatus.pending
        var saveSucceeded = false
        do {
            try context.save()
            saveSucceeded = true
        } catch {
            print("[SyncService] Soft-delete save failed: \(error.localizedDescription)")
        }

        // Best-effort: immediately delete child records from remote.
        // Skip if save failed — children are still in local store; deleting them remotely would orphan them.
        guard saveSucceeded, !childDeleteItems.isEmpty else { return }
        do {
            try await authService.refreshIfNeeded()
            let batchSize = 25
            for (batchIndex, batchStart) in stride(from: 0, to: childDeleteItems.count, by: batchSize).enumerated() {
                let batch = Array(childDeleteItems[batchStart..<min(batchStart + batchSize, childDeleteItems.count)])
                var body: [String: Any] = ["items": batch]
                if batchIndex == 0 && !s3Keys.isEmpty { body["deleteS3Keys"] = s3Keys }
                _ = try await apiClient.post(path: "/sync", body: body)
            }
            print("[SyncService] Deleted \(checkIns.count) check-in(s) + \(photos.count) photo(s) from remote for \(monthDayKey)#\(year)")
        } catch {
            print("[SyncService] Remote child cleanup failed (tombstone will sync via pushPending): \(error.localizedDescription)")
        }
    }

    /// Delete a single photo from DynamoDB and S3, then remove locally.
    @MainActor
    func deletePhoto(_ photo: PhotoAsset, context: ModelContext) async {
        let photoId = photo.id.uuidString
        let s3Key = photo.s3Key
        let s3ThumbKey = photo.s3ThumbKey

        // Delete locally first
        context.delete(photo)
        var saveSucceeded = false
        do {
            try context.save()
            saveSucceeded = true
        } catch {
            print("[SyncService] Local photo delete failed: \(error.localizedDescription)")
        }

        // Best-effort remote cleanup — skip if save failed to avoid orphaning the remote record
        guard saveSucceeded else { return }
        do {
            try await authService.refreshIfNeeded()
            var body: [String: Any] = [
                "items": [["sk": "photo#\(photoId)", "operation": "delete"]]
            ]
            var s3Keys: [String] = []
            if let k = s3Key { s3Keys.append(k) }
            if let k = s3ThumbKey { s3Keys.append(k) }
            if !s3Keys.isEmpty { body["deleteS3Keys"] = s3Keys }
            _ = try await apiClient.post(path: "/sync", body: body)
            print("[SyncService] Deleted photo \(photoId) from remote")
        } catch {
            print("[SyncService] Remote photo delete failed (local already removed): \(error.localizedDescription)")
        }
    }

    /// Schedule a sync after a 1-second debounce delay.
    func scheduleDebouncedSync() {
        syncDebounceTask?.cancel()
        syncDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await syncAll()
        }
    }

    /// Start polling every `interval` seconds. Call from app foreground; stop when backgrounded.
    func startPeriodicSync(interval: TimeInterval = 15) {
        periodicTask?.cancel()
        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await syncAll()
            }
        }
    }

    /// Stop the periodic sync timer (call when app goes to background).
    func stopPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    /// Soft-delete a template so the tombstone propagates to other devices via pushPending.
    @MainActor
    func deleteTemplate(_ template: CheckInTemplate, context: ModelContext) async {
        let now = Date.now
        template.deletedAt = now
        template.updatedAt = now
        template.syncStatus = SyncStatus.pending
        do {
            try context.save()
        } catch {
            print("[SyncService] Template soft-delete save failed: \(error.localizedDescription)")
            return
        }
        scheduleDebouncedSync()
    }

    /// Remove duplicate templates (same label + type) caused by multi-device seeding.
    /// Keeps the one with the lowest sortOrder; deletes extras from DynamoDB then locally.
    @MainActor
    func deduplicateTemplates() async {
        let context = ModelContext(container)
        guard let all = try? context.fetch(FetchDescriptor<CheckInTemplate>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )) else { return }

        var seen: Set<String> = []
        var toDelete: [CheckInTemplate] = []

        for template in all {
            // Skip templates already pending deletion
            guard template.deletedAt == nil else { continue }
            let key = "\(template.label.lowercased())|\(template.type.rawValue)"
            if seen.contains(key) {
                toDelete.append(template)
            } else {
                seen.insert(key)
            }
        }

        guard !toDelete.isEmpty else { return }

        // Soft-delete duplicates so other devices see the tombstone on their next pull
        let now = Date.now
        for template in toDelete {
            template.deletedAt = now
            template.updatedAt = now
            template.syncStatus = SyncStatus.pending
        }
        try? context.save()

        // Push tombstones now (don't wait for debounce)
        do {
            try await authService.refreshIfNeeded()
            let tombstones: [[String: Any]] = toDelete.map { t in
                let deletedAtStr = Self.isoFormatter.string(from: now)
                return [
                    "sk": "template#\(t.id.uuidString)",
                    "data": ["id": t.id.uuidString, "deletedAt": deletedAtStr],
                    "updatedAt": deletedAtStr
                ]
            }
            let batchSize = 25
            for i in stride(from: 0, to: tombstones.count, by: batchSize) {
                let batch = Array(tombstones[i..<min(i + batchSize, tombstones.count)])
                _ = try await apiClient.post(path: "/sync", body: ["items": batch])
            }
            // Hard-delete locally after successful push
            for template in toDelete { context.delete(template) }
            try? context.save()
        } catch {
            print("[SyncService] Dedup tombstone push failed: \(error.localizedDescription)")
            // Templates stay soft-deleted locally; pushPending will retry
        }
        print("[SyncService] Removed \(toDelete.count) duplicate template(s)")
    }

    /// Remove duplicate CheckInValues — keeps the latest per (entry, templateId) pair.
    /// Fixes inflated counts caused by UUID mismatches during cross-device sync.
    @MainActor
    func deduplicateCheckInValues() async {
        let context = ModelContext(container)
        guard let all = try? context.fetch(FetchDescriptor<CheckInValue>()) else { return }

        // Group by (entry monthDayKey+year, templateId), keep latest updatedAt, delete the rest
        var latestByKey: [String: CheckInValue] = [:]
        for value in all {
            let entryKey = "\(value.entry?.monthDayKey ?? "nil")|\(value.entry?.year ?? 0)"
            let key = "\(entryKey)|\(value.templateId.uuidString)"
            if let existing = latestByKey[key] {
                if value.updatedAt > existing.updatedAt {
                    context.delete(existing)
                    latestByKey[key] = value
                } else {
                    context.delete(value)
                }
            } else {
                latestByKey[key] = value
            }
        }
        try? context.save()
        let removed = all.count - latestByKey.count
        if removed > 0 {
            print("[SyncService] Removed \(removed) duplicate check-in value(s)")
        }
    }

    /// Full sync: push pending, pull remote, sync photos.
    func syncAll() async {
        guard networkMonitor.isConnected else { return }
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        do {
            try await authService.refreshIfNeeded()
            try await pushPending()
            let serverTime = try await pullRemote()
            try await uploadPhotos()
            try await downloadPhotos()
            // Use server-side timestamp to avoid clock-skew misses on next pull
            lastSyncDate = serverTime ?? Date()
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
        var tombstoneCount = 0

        for entry in pendingEntries {
            if let deletedAt = entry.deletedAt {
                // Tombstone: push a marker so other devices know this entry was deleted
                let deletedAtStr = Self.isoFormatter.string(from: deletedAt)
                items.append([
                    "sk": "entry#\(entry.monthDayKey)#\(entry.year)",
                    "data": [
                        "monthDayKey": entry.monthDayKey,
                        "year": entry.year,
                        "weekday": entry.weekday,
                        "deletedAt": deletedAtStr
                    ],
                    "updatedAt": deletedAtStr
                ])
                tombstoneCount += 1
            } else {
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
                        "updatedAt": Self.isoFormatter.string(from: value.updatedAt)
                    ])
                }
            }
        }

        var templateTombstoneCount = 0
        for template in pendingTemplates {
            if let deletedAt = template.deletedAt {
                // Tombstone: propagate deletion to other devices
                let deletedAtStr = Self.isoFormatter.string(from: deletedAt)
                items.append([
                    "sk": "template#\(template.id.uuidString)",
                    "data": ["id": template.id.uuidString, "deletedAt": deletedAtStr],
                    "updatedAt": deletedAtStr
                ])
                templateTombstoneCount += 1
            } else {
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
                    "updatedAt": Self.isoFormatter.string(from: template.updatedAt)
                ])
            }
        }

        guard !items.isEmpty else { return }

        let batchSize = 25
        for i in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[i..<min(i + batchSize, items.count)])
            _ = try await apiClient.post(path: "/sync", body: ["items": batch])
        }

        let now = Date()
        for entry in pendingEntries {
            if entry.deletedAt != nil {
                context.delete(entry)
            } else {
                entry.syncStatus = SyncStatus.synced
                entry.lastSyncedAt = now
                for value in entry.safeCheckInValues {
                    value.syncStatus = SyncStatus.synced
                    value.lastSyncedAt = now
                }
            }
        }
        for template in pendingTemplates {
            if template.deletedAt != nil {
                // Hard-delete after tombstone pushed successfully
                context.delete(template)
            } else {
                template.syncStatus = SyncStatus.synced
                template.lastSyncedAt = now
            }
        }

        try context.save()
        print("[SyncService] Pushed \(items.count) items (\(tombstoneCount) entry tombstone(s), \(templateTombstoneCount) template tombstone(s))")
    }

    /// Pull remote changes since last sync. Returns the server-side timestamp for use as next `since`.
    @MainActor
    @discardableResult
    func pullRemote() async throws -> Date? {
        let context = ModelContext(container)

        var queryItems: [URLQueryItem] = []
        if let lastSync = loadLastSyncDate() {
            // Subtract 2 minutes to account for clock skew between devices and server.
            // LWW checks on upsert prevent duplicate application of already-seen items.
            let buffered = lastSync.addingTimeInterval(-120)
            queryItems.append(URLQueryItem(name: "since", value: Self.isoFormatter.string(from: buffered)))
        }

        let result = try await apiClient.get(path: "/sync", queryItems: queryItems)
        guard let remoteItems = result["items"] as? [[String: Any]] else { return nil }

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

        // Prefer server-returned timestamp to avoid local clock skew
        return (result["serverTime"] as? String).flatMap { Self.isoFormatter.date(from: $0) }
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

        // Handle tombstone: remote entry was deleted — only apply if deletedAt is the latest write.
        // If deletedAt < remoteUpdatedAt the entry was re-created after deletion (stale tombstone marker);
        // fall through to normal upsert so the re-created entry is restored locally.
        if let deletedAtStr = item["deletedAt"] as? String,
           let deletedAt = Self.isoFormatter.date(from: deletedAtStr),
           deletedAt >= remoteUpdatedAt {
            if let local = existing.first, deletedAt >= local.updatedAt {
                context.delete(local) // cascade removes photos + check-ins
            }
            return
        }

        if let local = existing.first {
            // Skip if local tombstone is newer than or equal to the remote update.
            // If remoteUpdatedAt > local.deletedAt, the remote is a re-create/re-edit that
            // wins LWW — clear the tombstone and apply the remote update below.
            if let localDeletedAt = local.deletedAt, localDeletedAt >= remoteUpdatedAt { return }
            if remoteUpdatedAt > local.updatedAt {
                local.deletedAt = nil
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

        let remoteUpdatedAt = (item["updatedAt"] as? String).flatMap { Self.isoFormatter.date(from: $0) } ?? Date.distantPast

        let predicate = #Predicate<CheckInTemplate> { $0.id == id }
        let existing = try context.fetch(FetchDescriptor<CheckInTemplate>(predicate: predicate))

        // Handle tombstone: template was deleted on another device
        if let deletedAtStr = item["deletedAt"] as? String,
           let deletedAt = Self.isoFormatter.date(from: deletedAtStr) {
            if let local = existing.first, deletedAt >= local.updatedAt {
                context.delete(local)
            }
            return
        }

        if let local = existing.first {
            // LWW: skip if local is newer or same age
            guard remoteUpdatedAt > local.updatedAt else { return }
            // Skip if local is a pending tombstone
            if local.deletedAt != nil { return }
            local.label = item["label"] as? String ?? local.label
            if let typeRaw = item["type"] as? String, let type = CheckInFieldType(rawValue: typeRaw) {
                local.type = type
            }
            local.isActive = item["isActive"] as? Bool ?? local.isActive
            local.sortOrder = item["sortOrder"] as? Int ?? local.sortOrder
            local.updatedAt = remoteUpdatedAt
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
            template.updatedAt = remoteUpdatedAt
            template.syncStatus = SyncStatus.synced
            template.lastSyncedAt = Date()
            context.insert(template)
        }
    }

    @MainActor
    private func upsertCheckInValue(_ item: [String: Any], sk: String, context: ModelContext) throws {
        // Parse sk: "checkin#MM-DD#YYYY#VALUE_UUID"
        let parts = sk.split(separator: "#")
        guard parts.count >= 4,
              let monthDayKey = parts.dropFirst().first.map(String.init),
              let year = Int(parts[2]),
              let valueIdString = parts.last.map(String.init),
              let valueId = UUID(uuidString: valueIdString) else { return }

        guard let templateId = (item["templateId"] as? String).flatMap(UUID.init) else { return }

        let remoteUpdatedAt = (item["updatedAt"] as? String)
            .flatMap { Self.isoFormatter.date(from: $0) } ?? Date.distantPast

        let entryPredicate = #Predicate<DiaryEntry> { $0.monthDayKey == monthDayKey && $0.year == year }
        guard let entry = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: entryPredicate)).first else { return }

        // Primary lookup: find by value UUID (exact match from same device)
        let byId = #Predicate<CheckInValue> { $0.id == valueId }
        if let local = try context.fetch(FetchDescriptor<CheckInValue>(predicate: byId)).first {
            guard remoteUpdatedAt > local.updatedAt else { return }
            if let b = item["boolValue"] as? Bool { local.boolValue = b }
            if let t = item["textValue"] as? String { local.textValue = t }
            if let n = item["numberValue"] as? Double { local.numberValue = n }
            local.updatedAt = remoteUpdatedAt
            local.syncStatus = SyncStatus.synced
            local.lastSyncedAt = Date()
            return
        }

        // Secondary lookup: find by templateId + entry (handles UUID mismatch across devices)
        let byTemplate = #Predicate<CheckInValue> { $0.templateId == templateId }
        let candidatesByTemplate = try context.fetch(FetchDescriptor<CheckInValue>(predicate: byTemplate))
        if let local = candidatesByTemplate.first(where: { $0.entry?.monthDayKey == monthDayKey && $0.entry?.year == year }) {
            guard remoteUpdatedAt > local.updatedAt else { return }
            if let b = item["boolValue"] as? Bool { local.boolValue = b }
            if let t = item["textValue"] as? String { local.textValue = t }
            if let n = item["numberValue"] as? Double { local.numberValue = n }
            local.updatedAt = remoteUpdatedAt
            local.syncStatus = SyncStatus.synced
            local.lastSyncedAt = Date()
            return
        }

        // Not found locally — insert as new record
        let value = CheckInValue(
            id: valueId,
            templateId: templateId,
            boolValue: item["boolValue"] as? Bool,
            textValue: item["textValue"] as? String,
            numberValue: item["numberValue"] as? Double
        )
        value.updatedAt = remoteUpdatedAt
        value.entry = entry
        value.syncStatus = SyncStatus.synced
        value.lastSyncedAt = Date()
        context.insert(value)
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
