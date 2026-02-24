import Foundation

struct ScriptParseResult: Sendable, Codable {
    var scenes: [ScriptScene]
    var characters: [ScriptCharacter]
}
