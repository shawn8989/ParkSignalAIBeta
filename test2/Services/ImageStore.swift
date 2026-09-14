import Foundation
import UIKit
import SwiftData

/// Local disk cache for photos, backed by a synced `PhotoBlob` when a `ModelContext`
/// is provided. The on-disk file is a fast local cache; the blob is what syncs across
/// the user's devices via CloudKit. On a device that has the model (synced) but not
/// the file, `loadImage` transparently rehydrates the file from the blob.
enum ImageStore {

    @discardableResult
    static func saveJPEG(_ image: UIImage, quality: CGFloat = 0.85, context: ModelContext? = nil) throws -> String {
        let filename = "sign-\(UUID().uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "ImageStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        try data.write(to: url(for: filename), options: .atomic)
        if let context { upsertBlob(filename: filename, data: data, in: context) }
        return filename
    }

    static func loadImage(named filename: String, context: ModelContext? = nil) -> UIImage? {
        // Fast path: the local cache file.
        if let img = UIImage(contentsOfFile: url(for: filename).path) { return img }
        // Cross-device path: rehydrate from the synced blob and re-cache to disk.
        guard let context, let data = blobData(filename: filename, in: context) else { return nil }
        try? data.write(to: url(for: filename), options: .atomic)
        return UIImage(data: data)
    }

    static func deleteImage(named filename: String, context: ModelContext? = nil) {
        try? FileManager.default.removeItem(at: url(for: filename))
        guard let context else { return }
        if let blob = blob(filename: filename, in: context) {
            context.delete(blob)
            try? context.save()
        }
    }

    static func url(for filename: String) -> URL {
        documentsURL().appendingPathComponent(filename)
    }

    // MARK: - Synced blob helpers

    private static func upsertBlob(filename: String, data: Data, in context: ModelContext) {
        if let existing = blob(filename: filename, in: context) {
            existing.data = data
        } else {
            context.insert(PhotoBlob(filename: filename, data: data))
        }
        try? context.save()
    }

    private static func blob(filename: String, in context: ModelContext) -> PhotoBlob? {
        let descriptor = FetchDescriptor<PhotoBlob>(predicate: #Predicate { $0.filename == filename })
        return (try? context.fetch(descriptor))?.first
    }

    private static func blobData(filename: String, in context: ModelContext) -> Data? {
        blob(filename: filename, in: context)?.data
    }

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
