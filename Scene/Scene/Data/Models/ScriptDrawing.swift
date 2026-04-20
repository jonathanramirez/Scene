import Foundation
import SwiftData

@Model
final class ScriptDrawing {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var pageIndex: Int
    var drawingData: Data
    var createdAt: Date
    var updatedAt: Date

    init(documentId: UUID, pageIndex: Int, drawingData: Data) {
        self.id = UUID()
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.drawingData = drawingData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
