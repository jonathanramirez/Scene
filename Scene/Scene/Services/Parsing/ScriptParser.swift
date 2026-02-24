import Foundation

actor ScriptParser {
    func parse(url: URL) async throws -> ScriptParseResult {
        let pages = try PDFTextExtractor.textByPage(url: url)
        let scenes = PDFOutlineBuilder.buildScenes(from: pages)

        var characters: [String: ScriptCharacter] = [:]
        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for line in lines {
                if ScriptFormatHeuristics.looksLikeCharacterCue(line) {
                    let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if characters[name] == nil {
                        characters[name] = ScriptCharacter(name: name, firstPage: pageIndex)
                    }
                }
            }
        }

        let sortedChars = Array(characters.values).sorted { $0.name < $1.name }
        return ScriptParseResult(scenes: scenes, characters: sortedChars)
    }
}
