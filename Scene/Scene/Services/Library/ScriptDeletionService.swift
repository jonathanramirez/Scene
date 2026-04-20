import Foundation
import SwiftData

@MainActor
enum ScriptDeletionService {
    static func delete(document: ScriptDocument, from context: ModelContext) throws {
        let documentID = document.id
        let fileURL = document.fileURL

        try deleteRecords(of: ScriptDrawing.self, matching: #Predicate<ScriptDrawing> { $0.documentId == documentID }, from: context)
        try deleteRecords(of: ScriptNote.self, matching: #Predicate<ScriptNote> { $0.documentId == documentID }, from: context)
        try deleteRecords(of: ScriptBookmark.self, matching: #Predicate<ScriptBookmark> { $0.documentId == documentID }, from: context)
        try deleteRecords(of: ScriptReadingSession.self, matching: #Predicate<ScriptReadingSession> { $0.documentId == documentID }, from: context)

        context.delete(document)
        try context.save()

        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func deleteRecords<ModelType: PersistentModel>(
        of _: ModelType.Type,
        matching predicate: Predicate<ModelType>,
        from context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<ModelType>(predicate: predicate)
        let records = try context.fetch(descriptor)
        for record in records {
            context.delete(record)
        }
    }
}
