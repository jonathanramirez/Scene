import SwiftData
import SwiftUI

private struct PracticeSceneOption: Identifiable, Hashable {
    let id: String
    let title: String
    let startPage: Int?
    let endPage: Int?
}

struct PracticeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let document: ScriptDocument
    let parseResult: ScriptParseResult
    let initialFocusedTurnSequenceIndex: Int?

    @StateObject private var controller = ScriptPracticeSessionController()
    @State private var selectedCharacter = ""
    @State private var selectedSceneID = PracticeSceneOption.allScenesID
    @State private var onlyScenesWithSelectedCharacter = true
    @State private var responseWindow: Double = 4
    @State private var betweenTurnsPause: Double = 0.8
    @State private var speakSelectedCharacter = false
    @State private var hideSelectedDialogue = true
    @State private var revealCurrentLine = false
    @State private var noteDraft = ""
    @State private var focusedTurnSequenceIndex: Int?

    init(document: ScriptDocument, parseResult: ScriptParseResult, initialFocusedTurnSequenceIndex: Int? = nil) {
        self.document = document
        self.parseResult = parseResult
        self.initialFocusedTurnSequenceIndex = initialFocusedTurnSequenceIndex
        _focusedTurnSequenceIndex = State(initialValue: initialFocusedTurnSequenceIndex)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Character") {
                    Picker("Your role", selection: $selectedCharacter) {
                        ForEach(availableCharacters, id: \.self) { character in
                            Text(character).tag(character)
                        }
                    }

                    if !selectedCharacter.isEmpty {
                        Text("\(selectedCharacterTurnCount) turns across \(selectedCharacterPageCount) pages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Scene") {
                    if availableSceneOptions.count > 1 {
                        Picker("Practice range", selection: $selectedSceneID) {
                            ForEach(availableSceneOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }

                        Toggle("Only scenes with my role", isOn: $onlyScenesWithSelectedCharacter)
                    } else {
                        Text("No indexed scenes yet. Practice will use the full script.")
                            .foregroundStyle(.secondary)
                    }

                    Text(sceneSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Playback") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(controller.statusText)
                            .font(.headline)

                        Stepper("Pause for your line: \(responseWindow.formatted(.number.precision(.fractionLength(1))))s", value: $responseWindow, in: 1...12, step: 0.5)
                        Stepper("Pause between turns: \(betweenTurnsPause.formatted(.number.precision(.fractionLength(1))))s", value: $betweenTurnsPause, in: 0...4, step: 0.2)

                        Toggle("Read my lines too", isOn: $speakSelectedCharacter)
                        Toggle("Hide my lines in preview", isOn: $hideSelectedDialogue)

                        HStack {
                            Button(controller.isPlaying ? "Rehearsing..." : "Start Rehearsal") {
                                startRehearsal()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isPlaying || selectedCharacter.isEmpty || filteredTurns.isEmpty)

                            Button("Stop") {
                                controller.stop()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!controller.isPlaying)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Current Cue") {
                    if let activeTurn {
                        cueCard(for: activeTurn, allowsReveal: true)
                    } else {
                        Text("Build the index and choose a character to start rehearsing.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quick Note") {
                    TextEditor(text: $noteDraft)
                        .frame(minHeight: 100)

                    Button("Save Note") {
                        saveNote()
                    }
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeTurn == nil)
                }

                Section("Upcoming Turns") {
                    if previewTurns.isEmpty {
                        Text("No dialogue turns detected in this script.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(previewTurns) { turn in
                            cueCard(for: turn, allowsReveal: false)
                        }
                    }
                }
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let focusedTurn = focusedTurn {
                selectedCharacter = focusedTurn.characterName
            } else if selectedCharacter.isEmpty {
                selectedCharacter = availableCharacters.first ?? ""
            }
            resetSceneSelectionIfNeeded()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: selectedCharacter) { _, _ in
            controller.stop()
            revealCurrentLine = false
            if focusedTurn?.characterName != selectedCharacter {
                focusedTurnSequenceIndex = nil
            }
            resetSceneSelectionIfNeeded()
        }
        .onChange(of: controller.currentTurn?.sequenceIndex ?? -1) { _, _ in
            revealCurrentLine = false
            if let currentSequenceIndex = controller.currentTurn?.sequenceIndex {
                focusedTurnSequenceIndex = currentSequenceIndex
            }
        }
        .onChange(of: onlyScenesWithSelectedCharacter) { _, _ in
            controller.stop()
            resetSceneSelectionIfNeeded()
        }
        .onChange(of: selectedSceneID) { _, _ in
            if let focusedTurn,
               let matchingScene = sceneRanges.first(where: { sceneRange in
                   focusedTurn.pageIndex >= sceneRange.startPage && focusedTurn.pageIndex <= sceneRange.endPage
               }),
               selectedSceneID != matchingScene.id.uuidString {
                focusedTurnSequenceIndex = nil
            }
        }
    }

    private var availableCharacters: [String] {
        let charactersWithDialogue = Set(parseResult.dialogueTurns.map(\.characterName))
        return parseResult.characters
            .map(\.name)
            .filter { charactersWithDialogue.contains($0) }
    }

    private var activeTurn: ScriptDialogueTurn? {
        if let currentTurn = controller.currentTurn,
           filteredTurns.contains(where: { $0.id == currentTurn.id }) {
            return currentTurn
        }

        if let focusedTurn,
           filteredTurns.contains(where: { $0.id == focusedTurn.id }) {
            return focusedTurn
        }

        return filteredTurns.first
    }

    private var focusedTurn: ScriptDialogueTurn? {
        guard let focusedTurnSequenceIndex else { return nil }
        return parseResult.dialogueTurns.first { $0.sequenceIndex == focusedTurnSequenceIndex }
    }

    private var previewTurns: [ScriptDialogueTurn] {
        guard !filteredTurns.isEmpty else { return [] }

        let currentSequenceIndex = activeTurn?.sequenceIndex ?? filteredTurns.first?.sequenceIndex ?? 0
        let currentIndex = filteredTurns.firstIndex(where: { $0.sequenceIndex == currentSequenceIndex }) ?? 0
        let startIndex = max(0, currentIndex - 1)
        let endIndex = min(filteredTurns.count, startIndex + 8)
        return Array(filteredTurns[startIndex..<endIndex])
    }

    private var selectedCharacterTurnCount: Int {
        filteredTurns.filter { $0.characterName == selectedCharacter }.count
    }

    private var selectedCharacterPageCount: Int {
        Set(filteredTurns.filter { $0.characterName == selectedCharacter }.map(\.pageIndex)).count
    }

    private var availableSceneOptions: [PracticeSceneOption] {
        let dynamicScenes = sceneRanges.compactMap { sceneRange -> PracticeSceneOption? in
            if onlyScenesWithSelectedCharacter,
               !sceneRange.turns.contains(where: { $0.characterName == selectedCharacter }) {
                return nil
            }

            return PracticeSceneOption(
                id: sceneRange.id.uuidString,
                title: "#\(sceneRange.index) \(sceneRange.heading)",
                startPage: sceneRange.startPage,
                endPage: sceneRange.endPage
            )
        }

        return [PracticeSceneOption.allScenes] + dynamicScenes
    }

    private var filteredTurns: [ScriptDialogueTurn] {
        if let focusedTurn {
            return turnsForSelection(containing: focusedTurn)
        }

        guard let selectedScene = availableSceneOptions.first(where: { $0.id == selectedSceneID }),
              selectedScene.id != PracticeSceneOption.allScenesID,
              let startPage = selectedScene.startPage,
              let endPage = selectedScene.endPage else {
            return turnsForAllScenes
        }

        return parseResult.dialogueTurns.filter { turn in
            turn.pageIndex >= startPage && turn.pageIndex <= endPage
        }
    }

    private func turnsForSelection(containing turn: ScriptDialogueTurn) -> [ScriptDialogueTurn] {
        if let sceneRange = sceneRanges.first(where: { sceneRange in
            turn.pageIndex >= sceneRange.startPage && turn.pageIndex <= sceneRange.endPage
        }) {
            return parseResult.dialogueTurns.filter { candidate in
                candidate.pageIndex >= sceneRange.startPage && candidate.pageIndex <= sceneRange.endPage
            }
        }

        return turnsForAllScenes
    }

    private var turnsForAllScenes: [ScriptDialogueTurn] {
        if onlyScenesWithSelectedCharacter, selectedSceneID == PracticeSceneOption.allScenesID, !selectedCharacter.isEmpty {
            let pagesWithSelectedCharacter = Set(
                parseResult.dialogueTurns
                    .filter { $0.characterName == selectedCharacter }
                    .map(\.pageIndex)
            )

            if !pagesWithSelectedCharacter.isEmpty {
                return parseResult.dialogueTurns.filter { pagesWithSelectedCharacter.contains($0.pageIndex) }
            }
        }

        return parseResult.dialogueTurns
    }

    private var sceneSummaryText: String {
        if filteredTurns.isEmpty {
            return "No dialogue found for this selection."
        }

        let totalTurns = filteredTurns.count
        let ownTurns = filteredTurns.filter { $0.characterName == selectedCharacter }.count
        let pages = Set(filteredTurns.map(\.pageIndex)).count
        return "\(totalTurns) turns, \(ownTurns) yours, across \(pages) pages."
    }

    private var sceneRanges: [PracticeSceneRange] {
        let sortedScenes = parseResult.scenes.sorted { $0.startPage < $1.startPage }

        return sortedScenes.enumerated().map { index, scene in
            let nextStartPage = sortedScenes.indices.contains(index + 1) ? sortedScenes[index + 1].startPage : nil
            let inferredEndPage = scene.endPage ?? nextStartPage.map { max(scene.startPage, $0 - 1) } ?? parseResult.dialogueTurns.map(\.pageIndex).max() ?? scene.startPage

            let turns = parseResult.dialogueTurns.filter { turn in
                turn.pageIndex >= scene.startPage && turn.pageIndex <= inferredEndPage
            }

            return PracticeSceneRange(
                id: scene.id,
                index: scene.index,
                heading: scene.heading,
                startPage: scene.startPage,
                endPage: inferredEndPage,
                turns: turns
            )
        }
    }

    @ViewBuilder
    private func cueCard(for turn: ScriptDialogueTurn, allowsReveal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(turn.characterName)
                    .font(.headline)

                Spacer()

                Text("Page \(turn.pageIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let parenthetical = turn.parenthetical, !parenthetical.isEmpty {
                Text(parenthetical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let qualifierSummary = turn.qualifierSummary {
                Text(qualifierSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let suggestedPauseAfter = turn.suggestedPauseAfter, suggestedPauseAfter > 0 {
                Text("Suggested beat: \(suggestedPauseAfter.formatted(.number.precision(.fractionLength(1))))s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if shouldHideDialogue(for: turn) {
                Text("Your line is hidden for recall practice.")
                    .foregroundStyle(.secondary)

                if allowsReveal {
                    Button(revealCurrentLine ? "Hide Line" : "Reveal Line") {
                        revealCurrentLine.toggle()
                    }
                    .buttonStyle(.bordered)

                    if revealCurrentLine {
                        Text(turn.dialogue)
                            .font(.body)
                    }
                }
            } else {
                Text(turn.dialogue)
                    .font(.body)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(for: turn))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardBorderColor(for: turn), lineWidth: isActiveTurn(turn) ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.vertical, 4)
    }

    private func shouldHideDialogue(for turn: ScriptDialogueTurn) -> Bool {
        hideSelectedDialogue && turn.characterName == selectedCharacter && !revealCurrentLine
    }

    private func startRehearsal() {
        controller.start(
            turns: filteredTurns,
            selectedCharacter: selectedCharacter,
            responseWindow: responseWindow,
            betweenTurnsPause: betweenTurnsPause,
            speakSelectedCharacter: speakSelectedCharacter
        )
    }

    private func saveNote() {
        guard let activeTurn else { return }

        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ScriptNote(
            documentId: document.id,
            pageIndex: activeTurn.pageIndex,
            text: trimmed,
            dialogueTurnSequenceIndex: activeTurn.sequenceIndex,
            anchoredCharacterName: activeTurn.characterName,
            anchoredDialogueSnippet: String(activeTurn.dialogue.prefix(160)),
            anchoredQualifier: activeTurn.qualifierSummary
        )

        modelContext.insert(note)
        try? modelContext.save()
        noteDraft = ""
    }

    private func resetSceneSelectionIfNeeded() {
        let validIDs = Set(availableSceneOptions.map(\.id))

        if let focusedTurn,
           let matchingScene = sceneRanges.first(where: { sceneRange in
               focusedTurn.pageIndex >= sceneRange.startPage && focusedTurn.pageIndex <= sceneRange.endPage
           }) {
            selectedSceneID = matchingScene.id.uuidString
            return
        }

        if !validIDs.contains(selectedSceneID) {
            selectedSceneID = PracticeSceneOption.allScenesID
        }
    }

    private func isActiveTurn(_ turn: ScriptDialogueTurn) -> Bool {
        controller.currentTurn?.id == turn.id
    }

    private func isSelectedCharacterTurn(_ turn: ScriptDialogueTurn) -> Bool {
        turn.characterName == selectedCharacter
    }

    private func cardBackground(for turn: ScriptDialogueTurn) -> Color {
        if isActiveTurn(turn) {
            return isSelectedCharacterTurn(turn) ? Color.orange.opacity(0.22) : Color.blue.opacity(0.18)
        }

        if isSelectedCharacterTurn(turn) {
            return Color.orange.opacity(0.10)
        }

        return Color(.secondarySystemBackground)
    }

    private func cardBorderColor(for turn: ScriptDialogueTurn) -> Color {
        if isActiveTurn(turn) {
            return isSelectedCharacterTurn(turn) ? .orange : .blue
        }

        if isSelectedCharacterTurn(turn) {
            return .orange.opacity(0.5)
        }

        return .secondary.opacity(0.18)
    }
}

private struct PracticeSceneRange {
    let id: UUID
    let index: Int
    let heading: String
    let startPage: Int
    let endPage: Int
    let turns: [ScriptDialogueTurn]
}

private extension PracticeSceneOption {
    static let allScenesID = "all-scenes"
    static let allScenes = PracticeSceneOption(
        id: allScenesID,
        title: "All Scenes",
        startPage: nil,
        endPage: nil
    )
}
