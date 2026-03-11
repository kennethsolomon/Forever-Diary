import AppKit
import Foundation

/// macOS image compression pipeline — mirrors iOS UIImage helpers.
struct MacImageHelper {

    /// Resize and compress image data to JPEG. Returns nil if conversion fails.
    static func compress(
        _ data: Data,
        maxDimension: CGFloat = 4096,
        quality: CGFloat = 0.85
    ) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        return jpeg(resized, quality: quality)
    }

    /// Generate a square thumbnail from image data. Returns nil if conversion fails.
    static func thumbnail(
        _ data: Data,
        size: CGFloat = 300,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let thumb = squareCrop(image, to: size)
        return jpeg(thumb, quality: quality)
    }

    // MARK: - Private

    private static func resizeIfNeeded(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return draw(image, into: newSize)
    }

    private static func squareCrop(_ image: NSImage, to dimension: CGFloat) -> NSImage {
        let size = image.size
        let side = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        let target = CGSize(width: dimension, height: dimension)
        let result = NSImage(size: target)
        result.lockFocus()
        let destRect = CGRect(origin: .zero, size: target)
        image.draw(in: destRect, from: cropRect, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    private static func draw(_ image: NSImage, into size: CGSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }

    private static func jpeg(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}
