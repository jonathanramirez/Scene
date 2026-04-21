import Foundation
import SwiftData

@Model
final class ScriptParseCache {
    @Attribute(.unique) var documentId: UUID
    /// Bump this string in ParseCacheService.parserVersion to invalidate all caches.
    var parserVersion: String
    /// JSON-encoded ScriptParseResult
    var resultData: Data
    var indexedAt: Date

    init(documentId: UUID, parserVersion: String, resultData: Data) {
        self.documentId = documentId
        self.parserVersion = parserVersion
        self.resultData = resultData
        self.indexedAt = Date()
    }
}
