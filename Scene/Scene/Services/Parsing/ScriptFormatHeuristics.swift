import Foundation

enum ScriptFormatHeuristics {
    /// Scene headings in US screenplays commonly start with INT./EXT./INT-EXT/I/E.
    nonisolated static func isSceneHeading(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 5 else { return false }
        let u = s.uppercased()

        // Conservative checks
        if u.hasPrefix("INT.") || u.hasPrefix("EXT.") { return true }
        if u.hasPrefix("INT/EXT.") || u.hasPrefix("INT.-EXT.") || u.hasPrefix("INT-EXT.") { return true }
        if u.hasPrefix("I/E.") { return true }

        return false
    }

    /// Character cues: usually ALL CAPS, not too long, not a transition.
    nonisolated static func looksLikeCharacterCue(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 2 && s.count <= 30 else { return false }
        guard !s.hasSuffix(":") else { return false }

        // Must be mostly uppercase letters/spaces/'./()- and no colon at end
        let u = s.uppercased()
        guard s == u else { return false }

        // Exclude transitions
        if isTransition(s) { return false }

        // Exclude scene headings
        if isSceneHeading(s) { return false }

        // Exclude common non-character cues
        if u == "CONTINUED" || u == "THE END" { return false }

        return true
    }

    nonisolated static func isTransition(_ line: String) -> Bool {
        let u = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.hasSuffix(" TO:") { return true }
        if u == "FADE IN:" || u == "FADE OUT." || u == "FADE OUT:" { return true }
        if u.contains("CUT TO") || u.contains("FADE") || u.contains("DISSOLVE") { return true }
        if u.contains("SMASH CUT") || u.contains("MATCH CUT") || u.contains("BACK TO") { return true }
        return false
    }

    nonisolated static func isParenthetical(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 3 && s.count <= 80 && s.hasPrefix("(") && s.hasSuffix(")")
    }

    nonisolated static func isDialogueContinuationMarker(_ line: String) -> Bool {
        let u = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return u == "MORE" || u == "(MORE)"
    }

    nonisolated static func normalizedCharacterName(from line: String) -> String? {
        characterCueComponents(from: line)?.name
    }

    nonisolated static func characterCueComponents(from line: String) -> CharacterCueComponents? {
        guard looksLikeCharacterCue(line) else { return nil }

        var normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^", with: "")

        var qualifiers: [String] = []
        while let range = normalized.range(of: #"\s*\([^)]+\)\s*$"#, options: .regularExpression) {
            let captured = String(normalized[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty {
                qualifiers.insert(captured.uppercased(), at: 0)
            }
            normalized.removeSubrange(range)
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !normalized.isEmpty else { return nil }

        let normalizedQualifiers = qualifiers.map { qualifier in
            qualifier
                .replacingOccurrences(of: "CONT’D", with: "CONT'D")
                .replacingOccurrences(of: "VO", with: "V.O.")
                .replacingOccurrences(of: "O.S", with: "O.S.")
        }

        let joinedQualifier = normalizedQualifiers.isEmpty ? nil : normalizedQualifiers.joined(separator: " · ")
        let isVoiceOver = normalizedQualifiers.contains { $0.contains("V.O.") || $0 == "VOICE OVER" }
        let isOffScreen = normalizedQualifiers.contains { $0.contains("O.S.") || $0 == "OFF SCREEN" }
        let isContinued = normalizedQualifiers.contains { $0.contains("CONT'D") || $0.contains("CONTINUED") }

        return CharacterCueComponents(
            name: normalized,
            qualifier: joinedQualifier,
            isVoiceOver: isVoiceOver,
            isOffScreen: isOffScreen,
            isContinued: isContinued
        )
    }

    nonisolated static func suggestedPauseDuration(from parenthetical: String?) -> Double? {
        guard let parenthetical else { return nil }
        let normalized = parenthetical.uppercased()

        if normalized.contains("LONG BEAT") || normalized.contains("LONG PAUSE") {
            return 1.5
        }
        if normalized.contains("BEAT") || normalized.contains("PAUSE") {
            return 0.8
        }
        if normalized.contains("THEN") {
            return 0.4
        }

        return nil
    }
}

struct CharacterCueComponents: Sendable, Hashable {
    let name: String
    let qualifier: String?
    let isVoiceOver: Bool
    let isOffScreen: Bool
    let isContinued: Bool
}
