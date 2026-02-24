import Foundation
import SwiftData

@Model
final class ScriptBookmark {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var pageIndex: Int
    var label: String?
    var createdAt: Date

    init(documentId: UUID, pageIndex: Int, label: String? = nil) {
        self.id = UUID()
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.label = label
        self.createdAt = Date()
    }
}
