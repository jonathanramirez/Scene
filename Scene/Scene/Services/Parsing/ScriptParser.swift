import Foundation

actor ScriptParser {
    func parse(url: URL) async throws -> ScriptParseResult {
        let pages = try PDFTextExtractor.textByPage(url: url).sorted { $0.pageIndex < $1.pageIndex }
        let scenes = PDFOutlineBuilder.buildScenes(from: pages)

        var characters: [String: ScriptCharacter] = [:]
        var dialogueTurns: [ScriptDialogueTurn] = []
        var pendingTurn: PendingDialogueTurn?
        var sequenceIndex = 0

        func registerCharacterIfNeeded(_ name: String, pageIndex: Int) {
            if characters.index(forKey: name) == nil {
                characters[name] = ScriptCharacter(name: name, firstPage: pageIndex)
            }
        }

        func flushPendingTurn() {
            guard let activePendingTurn = pendingTurn else { return }
            pendingTurn = nil

            let dialogue = activePendingTurn.dialogueLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !dialogue.isEmpty else { return }

            dialogueTurns.append(
                ScriptDialogueTurn(
                    pageIndex: activePendingTurn.pageIndex,
                    sequenceIndex: activePendingTurn.sequenceIndex,
                    characterName: activePendingTurn.characterName,
                    parenthetical: activePendingTurn.parentheticals.isEmpty ? nil : activePendingTurn.parentheticals.joined(separator: " "),
                    dialogue: dialogue,
                    characterQualifier: activePendingTurn.characterQualifier,
                    isVoiceOver: activePendingTurn.isVoiceOver,
                    isOffScreen: activePendingTurn.isOffScreen,
                    isContinued: activePendingTurn.isContinued,
                    suggestedPauseAfter: ScriptFormatHeuristics.suggestedPauseDuration(
                        from: activePendingTurn.parentheticals.joined(separator: " ")
                    )
                )
            )
        }

        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                if line.isEmpty {
                    flushPendingTurn()
                    continue
                }

                if ScriptFormatHeuristics.isSceneHeading(line) || ScriptFormatHeuristics.isTransition(line) {
                    flushPendingTurn()
                    continue
                }

                if let cue = ScriptFormatHeuristics.characterCueComponents(from: line) {
                    flushPendingTurn()
                    registerCharacterIfNeeded(cue.name, pageIndex: pageIndex)
                    pendingTurn = PendingDialogueTurn(
                        pageIndex: pageIndex,
                        sequenceIndex: sequenceIndex,
                        characterName: cue.name,
                        characterQualifier: cue.qualifier,
                        isVoiceOver: cue.isVoiceOver,
                        isOffScreen: cue.isOffScreen,
                        isContinued: cue.isContinued
                    )
                    sequenceIndex += 1
                    continue
                }

                guard var activePendingTurn = pendingTurn else { continue }

                if ScriptFormatHeuristics.isDialogueContinuationMarker(line) {
                    continue
                }

                if ScriptFormatHeuristics.isParenthetical(line) {
                    activePendingTurn.parentheticals.append(line)
                } else {
                    activePendingTurn.dialogueLines.append(line)
                }

                pendingTurn = activePendingTurn
            }
        }

        flushPendingTurn()

        let sortedChars = Array(characters.values).sorted { $0.name < $1.name }
        return ScriptParseResult(scenes: scenes, characters: sortedChars, dialogueTurns: dialogueTurns)
    }
}

private struct PendingDialogueTurn {
    let pageIndex: Int
    let sequenceIndex: Int
    let characterName: String
    var characterQualifier: String? = nil
    var isVoiceOver: Bool = false
    var isOffScreen: Bool = false
    var isContinued: Bool = false
    var parentheticals: [String] = []
    var dialogueLines: [String] = []
}
