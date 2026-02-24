import Foundation

struct ScriptScene: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var heading: String
    var startPage: Int
    var endPage: Int?
}
