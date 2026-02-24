import Foundation

enum ScriptFormatHeuristics {
    /// Scene headings in US screenplays commonly start with INT./EXT./INT-EXT/I/E.
    static func isSceneHeading(_ line: String) -> Bool {
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
    static func looksLikeCharacterCue(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 2 && s.count <= 30 else { return false }

        // Must be mostly uppercase letters/spaces/'./()- and no colon at end
        let u = s.uppercased()
        guard s == u else { return false }

        // Exclude transitions
        if u.contains("CUT TO") || u.contains("FADE") || u.contains("DISSOLVE") { return false }

        // Exclude scene headings
        if isSceneHeading(s) { return false }

        // Exclude common non-character cues
        if u == "CONTINUED" { return false }

        return true
    }
}
