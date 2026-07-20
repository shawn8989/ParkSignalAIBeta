import Foundation
import UIKit

enum ImageStore {

    static func saveJPEG(_ image: UIImage, quality: CGFloat = 0.85) throws -> String {
        let filename = "sign-\(UUID().uuidString).jpg"
        let url = documentsURL().appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "ImageStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        try data.write(to: url, options: .atomic)
        return filename
    }

    static func url(for filename: String) -> URL {
        documentsURL().appendingPathComponent(filename)
    }

    static func loadImage(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    static func deleteImage(named filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
