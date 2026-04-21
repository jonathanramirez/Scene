import Foundation
import SwiftData

@MainActor
enum ParseCacheService {

    /// Bump this string whenever the parser logic changes to invalidate all stored caches.
    static let parserVersion = "1.1"

    // MARK: - Read

    static func load(documentId: UUID, context: ModelContext) -> (result: ScriptParseResult, indexedAt: Date)? {
        guard let cache = fetchCache(documentId: documentId, context: context),
              cache.parserVersion == parserVersion,
              let result = try? JSONDecoder().decode(ScriptParseResult.self, from: cache.resultData)
        else { return nil }
        return (result, cache.indexedAt)
    }

    static func indexedAt(documentId: UUID, context: ModelContext) -> Date? {
        guard let cache = fetchCache(documentId: documentId, context: context),
              cache.parserVersion == parserVersion
        else { return nil }
        return cache.indexedAt
    }

    // MARK: - Write

    static func save(_ result: ScriptParseResult, documentId: UUID, context: ModelContext) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        if let existing = fetchCache(documentId: documentId, context: context) {
            existing.parserVersion = parserVersion
            existing.resultData = data
            existing.indexedAt = Date()
        } else {
            context.insert(ScriptParseCache(documentId: documentId, parserVersion: parserVersion, resultData: data))
        }
        try? context.save()
    }

    static func invalidate(documentId: UUID, context: ModelContext) {
        if let existing = fetchCache(documentId: documentId, context: context) {
            context.delete(existing)
            try? context.save()
        }
    }

    // MARK: - Private

    private static func fetchCache(documentId: UUID, context: ModelContext) -> ScriptParseCache? {
        var descriptor = FetchDescriptor<ScriptParseCache>(
            predicate: #Predicate { $0.documentId == documentId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
