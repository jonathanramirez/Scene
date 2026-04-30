import Foundation

struct ScriptDialogueTurn: Identifiable, Sendable, Codable, Hashable {
    var id: UUID = UUID()
    var pageIndex: Int
    var sequenceIndex: Int
    var scriptOrderIndex: Int
    var characterName: String
    var parenthetical: String?
    var dialogue: String
    var characterQualifier: String?
    var isVoiceOver: Bool
    var isOffScreen: Bool
    var isContinued: Bool
    var suggestedPauseAfter: Double?

    var spokenText: String {
        var parts: [String] = []

        if let parenthetical, !parenthetical.isEmpty {
            let cleaned = parenthetical
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            parts.append(cleaned)
        }

        parts.append(dialogue)
        return parts.joined(separator: ", ")
    }

    var qualifierSummary: String? {
        var tags: [String] = []

        if let characterQualifier, !characterQualifier.isEmpty {
            tags.append(characterQualifier)
        }
        if isVoiceOver, !tags.contains("V.O.") {
            tags.append("V.O.")
        }
        if isOffScreen, !tags.contains("O.S.") {
            tags.append("O.S.")
        }
        if isContinued {
            tags.append("CONT'D")
        }

        return tags.isEmpty ? nil : tags.joined(separator: " · ")
    }
}
