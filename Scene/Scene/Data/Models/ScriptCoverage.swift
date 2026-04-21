import Foundation
import SwiftData

@Model
final class ScriptCoverage {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var logline: String
    var synopsis: String
    var comments: String
    var recommendationRaw: String
    var createdAt: Date
    var updatedAt: Date

    enum Recommendation: String, CaseIterable, Identifiable {
        case pass      = "Pass"
        case consider  = "Consider"
        case recommend = "Recommend"

        var id: String { rawValue }

        var color: String {
            switch self {
            case .pass:      return "red"
            case .consider:  return "orange"
            case .recommend: return "green"
            }
        }
    }

    var recommendation: Recommendation {
        get { Recommendation(rawValue: recommendationRaw) ?? .consider }
        set { recommendationRaw = newValue.rawValue }
    }

    init(documentId: UUID) {
        self.id = UUID()
        self.documentId = documentId
        self.logline = ""
        self.synopsis = ""
        self.comments = ""
        self.recommendationRaw = Recommendation.consider.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
