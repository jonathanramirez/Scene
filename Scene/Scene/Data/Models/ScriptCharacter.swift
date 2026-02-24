import Foundation

struct ScriptCharacter: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var firstPage: Int?
}
