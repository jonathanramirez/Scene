import PDFKit
import UIKit

/// Caches PDF first-page thumbnails to disk under `<Caches>/Thumbnails/<documentId>.jpg`
/// so `ScriptDetailView` never re-renders the same thumbnail twice.
enum ThumbnailCacheService {

    private static let size = CGSize(width: 160, height: 220)

    // MARK: - Public API

    /// Returns a cached thumbnail synchronously, or nil if the cache is cold.
    static func cached(for documentId: String) -> UIImage? {
        guard let url = cacheURL(for: documentId) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Renders and caches the thumbnail in a background task, returning the result.
    /// Safe to call from any actor — all file I/O is detached.
    static func generate(pdfURL: URL, documentId: String) async -> UIImage? {
        // Return disk cache immediately when available
        if let hit = cached(for: documentId) { return hit }

        return await Task.detached(priority: .utility) { () -> UIImage? in
            guard let pdf = PDFDocument(url: pdfURL),
                  let page = pdf.page(at: 0) else { return nil }

            let image = page.thumbnail(of: size, for: .mediaBox)

            // Persist to disk
            if let data = image.jpegData(compressionQuality: 0.85),
               let url = cacheURL(for: documentId) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: url, options: .atomic)
            }

            return image
        }.value
    }

    /// Removes the cached thumbnail for a document (call on deletion).
    static func evict(for documentId: String) {
        guard let url = cacheURL(for: documentId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private static func cacheURL(for documentId: String) -> URL? {
        guard let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        return caches
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent("\(documentId).jpg")
    }
}
