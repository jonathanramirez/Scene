import Foundation
import SwiftData

@Model
final class ScriptDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalFileName: String
    var fileURL: URL?
    var createdAt: Date
    var lastOpenedAt: Date?

    // Keep security-scoped bookmark for Files imports
    var bookmarkData: Data?

    // Metadata
    var pageCount: Int
    var estimatedMinutes: Int

    init(title: String, originalFileName: String, fileURL: URL?, bookmarkData: Data?, pageCount: Int) {
        self.id = UUID()
        self.title = title
        self.originalFileName = originalFileName
        self.fileURL = fileURL
        self.bookmarkData = bookmarkData
        self.createdAt = Date()
        self.lastOpenedAt = nil
        self.pageCount = pageCount
        self.estimatedMinutes = pageCount // 1 page ≈ 1 minute
    }
}
