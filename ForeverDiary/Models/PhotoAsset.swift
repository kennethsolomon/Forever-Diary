import Foundation
import SwiftData

@Model
final class PhotoAsset {
    var id: UUID = UUID()

    @Attribute(.externalStorage)
    var imageData: Data = Data()

    @Attribute(.externalStorage)
    var thumbnailData: Data = Data()

    var createdAt: Date = Date.now

    var entry: DiaryEntry?

    init(
        id: UUID = UUID(),
        imageData: Data,
        thumbnailData: Data,
        createdAt: Date = .now
    ) {
        self.id = id
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
    }

    /// Max photos per entry (CloudKit asset size guard)
    static let maxPhotosPerEntry = 10

    /// Max file size per photo after compression (10MB)
    static let maxPhotoBytes = 10 * 1024 * 1024
}
