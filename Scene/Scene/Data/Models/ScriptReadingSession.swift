import Foundation
import SwiftData

enum ReadingMode: String, Codable {
    case firstRead
    case secondRead
}

@Model
final class ScriptReadingSession {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var modeRaw: String
    var lastPageIndex: Int
    var progress: Double
    var updatedAt: Date

    // Rehearsal context — restored on next launch so the app feels smart
    var selectedCharacter: String?
    var lastMode: String?          // "reader" | "practice" | "lyrics"

    var mode: ReadingMode {
        get { ReadingMode(rawValue: modeRaw) ?? .firstRead }
        set { modeRaw = newValue.rawValue }
    }

    init(documentId: UUID, mode: ReadingMode) {
        self.id = UUID()
        self.documentId = documentId
        self.modeRaw = mode.rawValue
        self.lastPageIndex = 0
        self.progress = 0
        self.updatedAt = Date()
        self.selectedCharacter = nil
        self.lastMode = nil
    }
}
