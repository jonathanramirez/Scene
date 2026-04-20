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
    var dialogueTurnSequenceIndex: Int?
    var anchoredCharacterName: String?
    var anchoredDialogueSnippet: String?
    var anchoredQualifier: String?

    // Optional highlight rect stored as string: "x,y,w,h"
    var rectString: String?

    init(
        documentId: UUID,
        pageIndex: Int,
        text: String,
        kind: NoteKind = .freeform,
        rectString: String? = nil,
        dialogueTurnSequenceIndex: Int? = nil,
        anchoredCharacterName: String? = nil,
        anchoredDialogueSnippet: String? = nil,
        anchoredQualifier: String? = nil
    ) {
        self.id = UUID()
        self.documentId = documentId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.kindRaw = kind.rawValue
        self.pageIndex = pageIndex
        self.text = text
        self.dialogueTurnSequenceIndex = dialogueTurnSequenceIndex
        self.anchoredCharacterName = anchoredCharacterName
        self.anchoredDialogueSnippet = anchoredDialogueSnippet
        self.anchoredQualifier = anchoredQualifier
        self.rectString = rectString
    }

    var noteKind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .freeform }
        set { kindRaw = newValue.rawValue }
    }

    var hasDialogueAnchor: Bool {
        dialogueTurnSequenceIndex != nil || anchoredCharacterName != nil || anchoredDialogueSnippet != nil
    }
}
