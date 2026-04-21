import Foundation
import SwiftData

enum ReadingSessionService {
    /// Fetches the existing session for a document, or creates one if none exists.
    @discardableResult
    static func fetchOrCreate(for documentId: UUID, in context: ModelContext) -> ScriptReadingSession {
        var descriptor = FetchDescriptor<ScriptReadingSession>(
            predicate: #Predicate { $0.documentId == documentId }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let session = ScriptReadingSession(documentId: documentId, mode: .firstRead)
        context.insert(session)
        try? context.save()
        return session
    }

    /// Persists rehearsal context (character, mode) so it survives app restarts.
    /// Pass `nil` to leave a field unchanged.
    static func updateRehearsal(
        documentId: UUID,
        selectedCharacter: String? = nil,
        lastMode: String? = nil,
        in context: ModelContext
    ) {
        var descriptor = FetchDescriptor<ScriptReadingSession>(
            predicate: #Predicate { $0.documentId == documentId }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]

        let session: ScriptReadingSession
        if let existing = try? context.fetch(descriptor).first {
            session = existing
        } else {
            session = ScriptReadingSession(documentId: documentId, mode: .firstRead)
            context.insert(session)
        }

        if let character = selectedCharacter { session.selectedCharacter = character }
        if let mode = lastMode              { session.lastMode = mode }
        session.updatedAt = Date()
        try? context.save()
    }

    /// Updates page index and progress for a document's session, creating one if absent.
    static func update(documentId: UUID, pageIndex: Int, totalPages: Int, in context: ModelContext) {
        var descriptor = FetchDescriptor<ScriptReadingSession>(
            predicate: #Predicate { $0.documentId == documentId }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]

        let session: ScriptReadingSession
        if let existing = try? context.fetch(descriptor).first {
            session = existing
        } else {
            session = ScriptReadingSession(documentId: documentId, mode: .firstRead)
            context.insert(session)
        }

        session.lastPageIndex = pageIndex
        session.progress = totalPages > 0 ? Double(pageIndex + 1) / Double(totalPages) : 0
        session.updatedAt = Date()
        try? context.save()
    }
}
