import Foundation

struct ScriptActionLine: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var pageIndex: Int
    var sequenceIndex: Int
    var scriptOrderIndex: Int
    var text: String
}
