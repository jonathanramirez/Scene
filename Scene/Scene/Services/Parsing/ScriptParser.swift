import Foundation

actor ScriptParser {
    func parse(url: URL) async throws -> ScriptParseResult {
        let pages = try PDFTextExtractor.textByPage(url: url).sorted { $0.pageIndex < $1.pageIndex }
        let scenes = PDFOutlineBuilder.buildScenes(from: pages)

        var characters: [String: ScriptCharacter] = [:]
        var dialogueTurns: [ScriptDialogueTurn] = []
        var actionLines: [ScriptActionLine] = []
        var pendingTurn: PendingDialogueTurn?
        var pendingAction: PendingActionLine?
        var sequenceIndex = 0
        var actionSequenceIndex = 0
        var scriptOrderIndex = 0

        func registerCharacterIfNeeded(_ name: String, pageIndex: Int) {
            if characters.index(forKey: name) == nil {
                characters[name] = ScriptCharacter(name: name, firstPage: pageIndex)
            }
        }

        func flushPendingAction() {
            guard let activePendingAction = pendingAction else { return }
            pendingAction = nil

            let text = activePendingAction.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !text.isEmpty else { return }

            actionLines.append(
                ScriptActionLine(
                    pageIndex: activePendingAction.pageIndex,
                    sequenceIndex: activePendingAction.sequenceIndex,
                    scriptOrderIndex: activePendingAction.scriptOrderIndex,
                    text: text
                )
            )
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
                    scriptOrderIndex: activePendingTurn.scriptOrderIndex,
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

        func leadingWhitespaceCount(in line: String) -> Int {
            line.prefix { $0 == " " || $0 == "\t" }.count
        }

        func nextMeaningfulLine(after index: Int, in lines: [String]) -> String? {
            guard index + 1 < lines.count else { return nil }

            for nextIndex in (index + 1)..<lines.count {
                let nextLine = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !nextLine.isEmpty {
                    return lines[nextIndex]
                }
            }

            return nil
        }

        func shouldKeepDialogueAcrossBlank(_ pendingTurn: PendingDialogueTurn, nextRawLine: String?) -> Bool {
            guard let nextRawLine else { return false }

            let nextLine = nextRawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nextLine.isEmpty,
                  !ScriptFormatHeuristics.isSceneHeading(nextLine),
                  !ScriptFormatHeuristics.isTransition(nextLine)
            else { return false }

            if ScriptFormatHeuristics.characterCueComponents(from: nextLine) != nil {
                return false
            }

            if let lastDialogueLine = pendingTurn.dialogueLines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
               !lastDialogueLine.isEmpty,
               !".!?".contains(lastDialogueLine.last ?? ".") {
                return true
            }

            guard let lastIndent = pendingTurn.dialogueIndents.last else { return false }
            let nextIndent = leadingWhitespaceCount(in: nextRawLine)
            return nextIndent > 0 && abs(nextIndent - lastIndent) <= 4
        }

        for (pageIndex, text) in pages {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (lineIndex, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                if line.isEmpty {
                    if let pendingTurn,
                       shouldKeepDialogueAcrossBlank(
                           pendingTurn,
                           nextRawLine: nextMeaningfulLine(after: lineIndex, in: lines)
                       ) {
                        continue
                    }
                    flushPendingTurn()
                    flushPendingAction()
                    continue
                }

                if ScriptFormatHeuristics.isSceneHeading(line) || ScriptFormatHeuristics.isTransition(line) {
                    flushPendingTurn()
                    flushPendingAction()
                    continue
                }

                if let cue = ScriptFormatHeuristics.characterCueComponents(from: line) {
                    flushPendingTurn()
                    flushPendingAction()
                    registerCharacterIfNeeded(cue.name, pageIndex: pageIndex)
                    pendingTurn = PendingDialogueTurn(
                        pageIndex: pageIndex,
                        sequenceIndex: sequenceIndex,
                        scriptOrderIndex: scriptOrderIndex,
                        characterName: cue.name,
                        characterQualifier: cue.qualifier,
                        isVoiceOver: cue.isVoiceOver,
                        isOffScreen: cue.isOffScreen,
                        isContinued: cue.isContinued
                    )
                    sequenceIndex += 1
                    scriptOrderIndex += 1
                    continue
                }

                guard var activePendingTurn = pendingTurn else {
                    if pendingAction == nil {
                        pendingAction = PendingActionLine(
                            pageIndex: pageIndex,
                            sequenceIndex: actionSequenceIndex,
                            scriptOrderIndex: scriptOrderIndex
                        )
                        actionSequenceIndex += 1
                        scriptOrderIndex += 1
                    }

                    pendingAction?.lines.append(line)
                    continue
                }

                if ScriptFormatHeuristics.isDialogueContinuationMarker(line) {
                    continue
                }

                if ScriptFormatHeuristics.isParenthetical(line) {
                    activePendingTurn.parentheticals.append(line)
                } else {
                    activePendingTurn.dialogueLines.append(line)
                    activePendingTurn.dialogueIndents.append(leadingWhitespaceCount(in: rawLine))
                }

                pendingTurn = activePendingTurn
            }
        }

        flushPendingTurn()
        flushPendingAction()

        let sortedChars = Array(characters.values).sorted { $0.name < $1.name }
        return ScriptParseResult(
            scenes: scenes,
            characters: sortedChars,
            dialogueTurns: dialogueTurns,
            actionLines: actionLines
        )
    }
}

private struct PendingDialogueTurn {
    let pageIndex: Int
    let sequenceIndex: Int
    let scriptOrderIndex: Int
    let characterName: String
    var characterQualifier: String? = nil
    var isVoiceOver: Bool = false
    var isOffScreen: Bool = false
    var isContinued: Bool = false
    var parentheticals: [String] = []
    var dialogueLines: [String] = []
    var dialogueIndents: [Int] = []
}

private struct PendingActionLine {
    let pageIndex: Int
    let sequenceIndex: Int
    let scriptOrderIndex: Int
    var lines: [String] = []
}
