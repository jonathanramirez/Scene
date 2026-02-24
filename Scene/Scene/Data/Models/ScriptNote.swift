import Foundation
import SwiftData

enum NoteKind: String, Codable {
    case freeform
    case highlight
}

@Model
final class ScriptNote {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var createdAt: Date
    var updatedAt: Date

    var kindRaw: String
    var pageIndex: Int
    var text: String

    // Optional highlight rect stored as string: "x,y,w,h"
    var rectString: String?

    init(documentId: UUID, pageIndex: Int, text: String, kind: NoteKind = .freeform, rectString: String? = nil) {
        self.id = UUID()
        self.documentId = documentId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.kindRaw = kind.rawValue
        self.pageIndex = pageIndex
        self.text = text
        self.rectString = rectString
    }
}
