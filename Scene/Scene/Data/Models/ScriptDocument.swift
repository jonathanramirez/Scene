import Foundation
import SwiftData

@Model
final class ScriptDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalFileName: String
    /// Stored for legacy compatibility only. Use `resolvedFileURL` for all file access.
    var fileURL: URL?
    var createdAt: Date
    var lastOpenedAt: Date?

    // Not used; kept for schema compatibility
    var bookmarkData: Data?

    // Metadata
    var pageCount: Int
    var estimatedMinutes: Int

    /// Raw color name stored as string — see ScriptIconColor
    var iconColorRaw: String?

    var iconColor: ScriptIconColor {
        get { ScriptIconColor(rawValue: iconColorRaw ?? "") ?? .blue }
        set { iconColorRaw = newValue.rawValue }
    }

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

    /// Always reconstructs the file URL from the current sandbox Documents directory.
    /// Never use `fileURL` directly — it stores an absolute path that becomes
    /// stale after reinstalls or sandbox UUID changes.
    var resolvedFileURL: URL? {
        guard !originalFileName.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Scripts").appendingPathComponent(originalFileName)
    }
}
