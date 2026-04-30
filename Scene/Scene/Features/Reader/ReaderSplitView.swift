import AVFoundation
import SwiftData
import SwiftUI

struct ReaderSplitView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let document: ScriptDocument
    let initialJumpToPage: Int?
    let initialPracticeTurnSequenceIndex: Int?

    @Environment(ScriptSessionStore.self) private var sessionStore
    @StateObject private var vm = ReaderSplitViewModel()
    @StateObject private var pdfReadingController = ScriptPracticeSessionController()
    @State private var isShowingPractice = false
    @State private var isShowingLyrics = false
    @State private var isShowingSearch = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var hasAppliedInitialNavigation = false
    @State private var hasAutoOpenedPractice = false
    @State private var currentPageIndex = 0
    @State private var isShowingAddBookmark = false
    @State private var bookmarkLabelDraft = ""
    @State private var isShowingAddNote = false
    @State private var noteDraft = ""
    @State private var selectedNoteTag: NoteTag?
    @State private var selectedCharacterForDetail: ScriptCharacter? = nil
    @State private var activeSearchHighlight: PDFSearchHighlight?
    @State private var isShowingPDFReadingControls = false
    @State private var isPDFReadingOverlayEnabled = false
    @State private var isPDFReadingMuteAll = false
    @State private var mutedPDFReadingCharacters: Set<String> = []
    @State private var selectedPDFReadingCharacter = ""
    @State private var shouldReadOtherPDFCharacters = false
    @State private var pdfReadingRateMultiplier = 1.0
    @State private var shouldHighlightOnlyCurrentPDFLine = true
    @State private var arePDFActionHighlightsEnabled = true
    @State private var shouldReadPDFActionLines = false
    @State private var pdfPauseLengthMultiplier = 1.0
    @State private var isPDFReadingPlayerVisible = false
    @State private var isSelectingPDFReadingStart = false

    @Query(sort: \ScriptBookmark.createdAt, order: .reverse)
    private var allBookmarks: [ScriptBookmark]

    @Query(sort: \ScriptNote.updatedAt, order: .reverse)
    private var allNotes: [ScriptNote]

    private var bookmarks: [ScriptBookmark] {
        allBookmarks.filter { $0.documentId == document.id }
    }

    private var notes: [ScriptNote] {
        allNotes.filter { $0.documentId == document.id }
    }

    init(document: ScriptDocument, initialJumpToPage: Int? = nil, initialPracticeTurnSequenceIndex: Int? = nil) {
        self.document = document
        self.initialJumpToPage = initialJumpToPage
        self.initialPracticeTurnSequenceIndex = initialPracticeTurnSequenceIndex
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            if let url = document.resolvedFileURL, FileManager.default.fileExists(atPath: url.path) {
                readerDetail
            } else {
                fileMissingPlaceholder
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if !hasAppliedInitialNavigation {
                vm.jumpToPage = initialJumpToPage
                hasAppliedInitialNavigation = true
            }

            await vm.buildIndex(for: document, context: context)
            restoreRehearsalState()
            autoOpenPracticeIfNeeded()
        }
        .onChange(of: vm.parseResult?.dialogueTurns.count ?? 0) { _, _ in
            autoOpenPracticeIfNeeded()
        }
        .onChange(of: pdfReadingController.currentTurn?.sequenceIndex) { _, _ in
            guard pdfReadingController.isPlaying,
                  let turn = pdfReadingController.currentTurn
            else { return }
            vm.jumpToPage = turn.pageIndex
        }
        .sheet(isPresented: $isShowingPractice) {
            if let parseResult = vm.parseResult {
                PracticeSessionView(
                    document: document,
                    parseResult: parseResult,
                    initialFocusedTurnSequenceIndex: initialPracticeTurnSequenceIndex
                )
            }
        }
        .sheet(isPresented: $isShowingSearch) {
            ScriptSearchView(document: document) { match in
                activeSearchHighlight = PDFSearchHighlight(
                    query: match.query,
                    pageIndex: match.pageIndex,
                    occurrenceIndex: match.occurrenceIndex
                )
                vm.jumpToPage = match.pageIndex
            }
        }
        .sheet(isPresented: $isShowingPDFReadingControls) {
            if let parseResult = vm.parseResult {
                PDFReadingControlsView(
                    parseResult: parseResult,
                    isEnabled: $isPDFReadingOverlayEnabled,
                    isMuteAll: $isPDFReadingMuteAll,
                    mutedCharacters: $mutedPDFReadingCharacters,
                    selectedCharacter: $selectedPDFReadingCharacter,
                    readOtherCharacters: $shouldReadOtherPDFCharacters,
                    highlightActions: $arePDFActionHighlightsEnabled,
                    readActionLines: $shouldReadPDFActionLines,
                    pauseLengthMultiplier: $pdfPauseLengthMultiplier,
                    highlightOnlyCurrentLine: $shouldHighlightOnlyCurrentPDFLine,
                    isVoiceOverPlaying: pdfReadingController.isPlaying,
                    voiceOverStatus: pdfReadingController.statusText,
                    onStartVoiceOver: startPDFReadingVoiceOver,
                    onStopVoiceOver: stopPDFReadingVoiceOver
                )
            }
        }
        .sheet(item: $selectedCharacterForDetail) { character in
            if let parseResult = vm.parseResult {
                NavigationStack {
                    CharacterDetailView(character: character, parseResult: parseResult) { page in
                        vm.jumpToPage = page
                        selectedCharacterForDetail = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedCharacterForDetail = nil }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingLyrics) {
            if let parseResult = vm.parseResult {
                LyricsPracticeView(document: document, parseResult: parseResult)
            }
        }
    }

    private var readerDetail: some View {
        ReaderView(
            document: document,
            dialogueTurns: pdfHighlightTurns,
            dialogueHighlightSettings: PDFDialogueHighlightSettings(
                isEnabled: isPDFReadingOverlayEnabled,
                mutedCharacters: mutedPDFReadingCharacters,
                isMuteAll: isPDFReadingMuteAll,
                activeTurnSequenceIndex: pdfReadingController.spokenTurn?.sequenceIndex,
                isActiveTurnOnly: shouldHighlightOnlyCurrentPDFLine
            ),
            jumpToPage: $vm.jumpToPage,
            searchHighlight: $activeSearchHighlight,
            onPageChanged: { page in
                currentPageIndex = page
                sessionStore.session(for: document.id).currentPage = page
            },
            onDialogueTurnSelected: selectPDFReadingStart
        )
        .onChange(of: pdfReadingController.statusText) { _, status in
            if status == "Rehearsal complete" {
                isPDFReadingPlayerVisible = true
            }
        }
        .overlay(alignment: .bottom) {
            if isPDFReadingPlayerVisible || pdfReadingController.isPlaying || pdfReadingController.isPaused {
                PDFReadingPlayerOverlay(
                    status: pdfReadingController.statusText,
                    characterName: pdfReadingController.currentTurn?.characterName,
                    pauseRemainingSeconds: pdfReadingController.pauseRemainingSeconds,
                    isNextPage: isPDFReadingNextPage,
                    isPaused: pdfReadingController.isPaused,
                    rateMultiplier: pdfReadingRateMultiplier,
                    pauseMultiplier: pdfPauseLengthMultiplier,
                    isSelectingStart: isSelectingPDFReadingStart,
                    onTogglePause: togglePDFReadingPause,
                    onSkip: { pdfReadingController.skipCurrentTurn() },
                    onAdjustPause: { pdfReadingController.adjustCurrentPause(by: $0) },
                    onSelectPauseMultiplier: setPDFPauseLengthMultiplier,
                    onToggleStartSelection: togglePDFStartSelectionMode,
                    onClose: closePDFReadingPlayer,
                    onSelectRate: setPDFReadingRateMultiplier
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Close reader")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    noteDraft = ""
                    selectedNoteTag = nil
                    isShowingAddNote = true
                } label: {
                    Image(systemName: "note.text.badge.plus")
                }
                .accessibilityLabel("Add note")

                Button {
                    bookmarkLabelDraft = ""
                    isShowingAddBookmark = true
                } label: {
                    Image(systemName: "bookmark")
                }

                if vm.parseResult?.dialogueTurns.isEmpty == false {
                    Button {
                        togglePDFDialogueHighlights()
                    } label: {
                        Image(systemName: isPDFReadingOverlayEnabled ? "highlighter" : "highlighter")
                            .foregroundStyle(isPDFReadingOverlayEnabled ? .orange : .primary)
                    }
                    .accessibilityLabel(isPDFReadingOverlayEnabled ? "Hide dialogue highlights" : "Highlight dialogue")
                }

                Menu {
                    if let parseResult = vm.parseResult, !parseResult.dialogueTurns.isEmpty {
                        Button {
                            togglePDFDialogueHighlights()
                        } label: {
                            Label(
                                isPDFReadingOverlayEnabled ? "Hide Dialogue Highlights" : "Highlight All Dialogue",
                                systemImage: "highlighter"
                            )
                        }

                        Button {
                            isShowingPDFReadingControls = true
                        } label: {
                            Label("PDF Reading Controls", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button {
                            isShowingPractice = true
                        } label: {
                            Label("Practice Mode", systemImage: "mic")
                        }

                        Button {
                            isShowingLyrics = true
                        } label: {
                            Label("Lyrics Mode", systemImage: "text.alignleft")
                        }

                        Divider()
                    }

                    Button {
                        isShowingSearch = true
                    } label: {
                        Label("Search Script", systemImage: "magnifyingglass")
                    }

                    if vm.parseResult?.dialogueTurns.isEmpty == false {
                        Divider()
                    }

                    if vm.isParsing {
                        Label("Indexing…", systemImage: "gearshape")
                    } else {
                        Button {
                            Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                        } label: {
                            Label(
                                vm.indexedAt != nil ? "Reindex Script" : "Build Index",
                                systemImage: "wand.and.stars"
                            )
                        }
                    }
                } label: {
                    if vm.isParsing {
                        ProgressView()
                    } else {
                        Label("Rehearse", systemImage: "theatermasks")
                            .symbolVariant(vm.indexedAt != nil ? .none : .none)
                    }
                }
            }
        }
        .alert("Add Bookmark", isPresented: $isShowingAddBookmark) {
            TextField("Label (optional)", text: $bookmarkLabelDraft)
            Button("Add") { saveBookmark() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bookmarking page \(currentPageIndex + 1)")
        }
        .sheet(isPresented: $isShowingAddNote) {
            ReaderAddNoteView(
                pageIndex: currentPageIndex,
                text: $noteDraft,
                selectedTag: $selectedNoteTag,
                onCancel: {
                    isShowingAddNote = false
                },
                onSave: {
                    saveNote()
                }
            )
        }
    }

    private func saveBookmark() {
        let label = bookmarkLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = ScriptBookmark(
            documentId: document.id,
            pageIndex: currentPageIndex,
            label: label.isEmpty ? nil : label
        )
        context.insert(bookmark)
        try? context.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = ScriptNote(
            documentId: document.id,
            pageIndex: currentPageIndex,
            text: trimmed,
            tag: selectedNoteTag,
            rectString: defaultNoteAnchorString(for: currentPageIndex)
        )
        context.insert(note)
        try? context.save()
        noteDraft = ""
        selectedNoteTag = nil
        isShowingAddNote = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func defaultNoteAnchorString(for pageIndex: Int) -> String {
        let pageNoteCount = notes.filter { $0.pageIndex == pageIndex }.count
        let y = min(0.14 + (Double(pageNoteCount % 6) * 0.08), 0.58)
        return String(format: "%.3f,%.3f", 0.88, y)
    }

    private func startPDFReadingVoiceOver(character: String, readOtherCharacters: Bool, readActionLines: Bool) {
        startPDFReadingVoiceOver(
            character: character,
            readOtherCharacters: readOtherCharacters,
            readActionLines: readActionLines,
            startingAtSequenceIndex: nil
        )
    }

    private func startPDFReadingVoiceOver(
        character: String,
        readOtherCharacters: Bool,
        readActionLines: Bool,
        startingAtSequenceIndex: Int?
    ) {
        guard let parseResult = vm.parseResult else { return }
        let allTurns = pdfPlaybackTurns(from: parseResult)
        let upcomingTurns: [ScriptDialogueTurn]
        if let startingAtSequenceIndex,
           let startIndex = allTurns.firstIndex(where: { $0.sequenceIndex == startingAtSequenceIndex }) {
            upcomingTurns = Array(allTurns[startIndex...])
        } else {
            upcomingTurns = allTurns.filter { $0.pageIndex >= currentPageIndex }
        }
        let turns = upcomingTurns.isEmpty ? allTurns : upcomingTurns
        guard !turns.isEmpty, !character.isEmpty else { return }

        isPDFReadingPlayerVisible = true
        isSelectingPDFReadingStart = false
        isPDFReadingOverlayEnabled = true
        isPDFReadingMuteAll = false
        shouldHighlightOnlyCurrentPDFLine = true
        selectedPDFReadingCharacter = character
        mutedPDFReadingCharacters = readOtherCharacters ? [] : Set(pdfReadingCharacters.filter { $0 != character })
        if !arePDFActionHighlightsEnabled {
            mutedPDFReadingCharacters.insert(Self.actionCharacterName)
        }
        pdfReadingController.start(
            turns: turns,
            selectedCharacter: character,
            responseWindow: 0,
            betweenTurnsPause: 0.25,
            speakSelectedCharacter: true,
            speechRate: pdfReadingSpeechRate,
            speakOtherCharacters: readOtherCharacters,
            alwaysSpeakCharacters: readActionLines ? [Self.actionCharacterName] : [],
            neverSpeakCharacters: readActionLines ? [] : [Self.actionCharacterName],
            skippedTurnPause: 0.75,
            showSkippedTurns: readOtherCharacters || !readActionLines,
            pauseLengthMultiplier: pdfPauseLengthMultiplier
        )
    }

    private func stopPDFReadingVoiceOver() {
        pdfReadingController.stop()
    }

    private func closePDFReadingPlayer() {
        pdfReadingController.stop()
        isPDFReadingPlayerVisible = false
        isSelectingPDFReadingStart = false
    }

    private func togglePDFReadingPause() {
        if pdfReadingController.isPaused {
            pdfReadingController.resume()
        } else if pdfReadingController.isPlaying {
            pdfReadingController.pause()
        }
    }

    private func setPDFReadingRateMultiplier(_ multiplier: Double) {
        pdfReadingRateMultiplier = multiplier
        pdfReadingController.updateSpeechRate(pdfReadingSpeechRate)
    }

    private func togglePDFDialogueHighlights() {
        isPDFReadingOverlayEnabled.toggle()
        if isPDFReadingOverlayEnabled {
            isPDFReadingMuteAll = false
            shouldHighlightOnlyCurrentPDFLine = false
        }
    }

    private func setPDFPauseLengthMultiplier(_ multiplier: Double) {
        pdfPauseLengthMultiplier = multiplier
        pdfReadingController.updatePauseLengthMultiplier(multiplier)
    }

    private var isPDFReadingNextPage: Bool {
        guard let upcomingPage = pdfReadingController.upcomingTurn?.pageIndex else { return false }
        let referencePage = pdfReadingController.currentTurn?.pageIndex ?? currentPageIndex
        return upcomingPage != referencePage
    }

    private func togglePDFStartSelectionMode() {
        isSelectingPDFReadingStart.toggle()
        if isSelectingPDFReadingStart {
            isPDFReadingPlayerVisible = true
            isPDFReadingOverlayEnabled = true
            isPDFReadingMuteAll = false
            shouldHighlightOnlyCurrentPDFLine = false
        } else {
            shouldHighlightOnlyCurrentPDFLine = true
        }
    }

    private func selectPDFReadingStart(_ turn: ScriptDialogueTurn) {
        guard isSelectingPDFReadingStart || isPDFReadingPlayerVisible || pdfReadingController.isPlaying else { return }
        let character = selectedPDFReadingCharacter.isEmpty ? (pdfReadingCharacters.first ?? "") : selectedPDFReadingCharacter
        guard !character.isEmpty else { return }
        startPDFReadingVoiceOver(
            character: character,
            readOtherCharacters: shouldReadOtherPDFCharacters,
            readActionLines: shouldReadPDFActionLines,
            startingAtSequenceIndex: turn.sequenceIndex
        )
    }

    private var pdfReadingCharacters: [String] {
        guard let parseResult = vm.parseResult else { return [] }
        let speakers = Set(parseResult.dialogueTurns.map(\.characterName))
        return parseResult.characters
            .map(\.name)
            .filter { speakers.contains($0) }
            .sorted()
    }

    private var pdfReadingSpeechRate: Float {
        let rawRate = AVSpeechUtteranceDefaultSpeechRate * Float(pdfReadingRateMultiplier)
        return min(max(rawRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private static let actionCharacterName = "Action"
    private static let actionSequenceIndexOffset = 1_000_000

    private var pdfHighlightTurns: [ScriptDialogueTurn] {
        guard let parseResult = vm.parseResult else { return [] }
        var turns = parseResult.dialogueTurns
        let shouldIncludeActions = arePDFActionHighlightsEnabled || pdfReadingController.spokenTurn?.characterName == Self.actionCharacterName
        if shouldIncludeActions {
            turns.append(contentsOf: parseResult.actionLines.map(actionTurn(from:)))
        }
        return turns
    }

    private func pdfPlaybackTurns(from parseResult: ScriptParseResult) -> [ScriptDialogueTurn] {
        (parseResult.dialogueTurns + parseResult.actionLines.map(actionTurn(from:)))
            .sorted {
                if $0.scriptOrderIndex == $1.scriptOrderIndex {
                    return $0.sequenceIndex < $1.sequenceIndex
                }
                return $0.scriptOrderIndex < $1.scriptOrderIndex
            }
    }

    private func actionTurn(from action: ScriptActionLine) -> ScriptDialogueTurn {
        ScriptDialogueTurn(
            pageIndex: action.pageIndex,
            sequenceIndex: Self.actionSequenceIndexOffset + action.sequenceIndex,
            scriptOrderIndex: action.scriptOrderIndex,
            characterName: Self.actionCharacterName,
            parenthetical: nil,
            dialogue: action.text,
            characterQualifier: nil,
            isVoiceOver: true,
            isOffScreen: false,
            isContinued: false,
            suggestedPauseAfter: 0.35
        )
    }

    private var dialogueTurnCounts: [String: Int] {
        guard let parseResult = vm.parseResult else { return [:] }
        return parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
	}
}

private struct ReaderAddNoteView: View {
    @Environment(\.dismiss) private var dismiss

    let pageIndex: Int
    @Binding var text: String
    @Binding var selectedTag: NoteTag?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    tagCard
                    noteCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var tagCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteTag.allCases) { tag in
                        Button {
                            selectedTag = selectedTag == tag ? nil : tag
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tag.icon)
                                    .font(.caption)
                                Text(tag.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedTag == tag ? tag.color : tag.color.opacity(0.12))
                            .foregroundStyle(selectedTag == tag ? .white : tag.color)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReaderSidebarSectionHeader("Page \(pageIndex + 1)")

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }
}

private struct PDFReadingControlsView: View {
    @Environment(\.dismiss) private var dismiss

    let parseResult: ScriptParseResult
    @Binding var isEnabled: Bool
    @Binding var isMuteAll: Bool
    @Binding var mutedCharacters: Set<String>
    @Binding var selectedCharacter: String
    @Binding var readOtherCharacters: Bool
    @Binding var highlightActions: Bool
    @Binding var readActionLines: Bool
    @Binding var pauseLengthMultiplier: Double
    @Binding var highlightOnlyCurrentLine: Bool
    let isVoiceOverPlaying: Bool
    let voiceOverStatus: String
    let onStartVoiceOver: (String, Bool, Bool) -> Void
    let onStopVoiceOver: () -> Void

    private var characters: [String] {
        let speakers = Set(parseResult.dialogueTurns.map(\.characterName))
        return parseResult.characters
            .map(\.name)
            .filter { speakers.contains($0) }
            .sorted()
    }

    private var turnCounts: [String: Int] {
        parseResult.dialogueTurns.reduce(into: [:]) { counts, turn in
            counts[turn.characterName, default: 0] += 1
        }
    }

    private let pauseOptions: [(title: String, value: Double)] = [
        ("Short", 0.7),
        ("Natural", 1.0),
        ("Long", 1.4),
        ("Extra", 1.8)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Role", selection: $selectedCharacter) {
                        ForEach(characters, id: \.self) { character in
                            Text(character).tag(character)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        if isVoiceOverPlaying {
                            onStopVoiceOver()
                        } else {
                            isEnabled = true
                            isMuteAll = false
                            highlightOnlyCurrentLine = true
                            onStartVoiceOver(selectedRehearsalCharacter ?? "", readOtherCharacters, readActionLines)
                            dismiss()
                        }
                    } label: {
                        Label(
                            isVoiceOverPlaying ? "Stop Player" : "Start Player",
                            systemImage: isVoiceOverPlaying ? "stop.fill" : "speaker.wave.2.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(isVoiceOverPlaying ? .red : .primary)

                    Button {
                        startRehearsal()
                    } label: {
                        Label("Highlight Role", systemImage: "highlighter")
                    }
                    .disabled(selectedRehearsalCharacter == nil)
                } header: {
                    Text("Start")
                }

                Section {
                    Toggle("Other roles", isOn: $readOtherCharacters)
                        .disabled(isVoiceOverPlaying)

                    Toggle("Action narration", isOn: $readActionLines)
                        .disabled(isVoiceOverPlaying)

                    Toggle("Current line only", isOn: $highlightOnlyCurrentLine)

                    Picker("Pauses", selection: $pauseLengthMultiplier) {
                        ForEach(pauseOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isVoiceOverPlaying {
                        Label(voiceOverStatus, systemImage: "waveform")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice")
                }

                Section {
                    Toggle("Dialogue", isOn: $isEnabled)

                    Toggle("Action lines", isOn: $highlightActions)
                        .disabled(!isEnabled)

                    Toggle("Hide all roles", isOn: $isMuteAll)
                        .disabled(!isEnabled)

                    HStack {
                        Button {
                            mutedCharacters.removeAll()
                            isMuteAll = false
                            isEnabled = true
                        } label: {
                            Label("Show All", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            isMuteAll = true
                            isEnabled = true
                        } label: {
                            Label("Hide All", systemImage: "eye.slash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("PDF Highlights")
                }

                Section("Roles") {
                    ForEach(characters, id: \.self) { character in
                        Toggle(isOn: binding(for: character)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(PDFDialogueHighlightPalette.swiftUIColor(
                                        for: character,
                                        allCharacters: characters
                                    ))
                                    .frame(width: 14, height: 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character)
                                        .font(.body.weight(.medium))

                                    Text("\(turnCounts[character, default: 0]) turns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!isEnabled || isMuteAll)
                    }
                }
            }
            .navigationTitle("PDF Reading")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedCharacter.isEmpty || !characters.contains(selectedCharacter) {
                    selectedCharacter = firstVisibleCharacter ?? characters.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var selectedRehearsalCharacter: String? {
        characters.contains(selectedCharacter) ? selectedCharacter : characters.first
    }

    private var firstVisibleCharacter: String? {
        characters.first { !mutedCharacters.contains($0) }
    }

    private func startRehearsal() {
        guard let selectedRehearsalCharacter else { return }
        mutedCharacters = Set(characters.filter { $0 != selectedRehearsalCharacter })
        isMuteAll = false
        isEnabled = true
        highlightOnlyCurrentLine = false
        dismiss()
    }

    private func binding(for character: String) -> Binding<Bool> {
        Binding(
            get: { !mutedCharacters.contains(character) },
            set: { isVisible in
                isEnabled = true
                isMuteAll = false
                if isVisible {
                    mutedCharacters.remove(character)
                } else {
                    mutedCharacters.insert(character)
                }
            }
        )
    }
}

private struct PDFReadingPlayerOverlay: View {
    let status: String
    let characterName: String?
    let pauseRemainingSeconds: Double?
    let isNextPage: Bool
    let isPaused: Bool
    let rateMultiplier: Double
    let pauseMultiplier: Double
    let isSelectingStart: Bool
    let onTogglePause: () -> Void
    let onSkip: () -> Void
    let onAdjustPause: (Double) -> Void
    let onSelectPauseMultiplier: (Double) -> Void
    let onToggleStartSelection: () -> Void
    let onClose: () -> Void
    let onSelectRate: (Double) -> Void

    private let rates: [(label: String, value: Double)] = [
        ("0.8x", 0.8),
        ("1x", 1.0),
        ("1.25x", 1.25),
        ("1.5x", 1.5)
    ]
    private let pauseRates: [(label: String, value: Double)] = [
        ("Short", 0.7),
        ("Natural", 1.0),
        ("Long", 1.4),
        ("Extra", 1.8)
    ]

    var body: some View {
        HStack(spacing: 14) {
            statusCluster
                .frame(maxWidth: .infinity, alignment: .leading)

            if pauseRemainingSeconds != nil {
                pauseNudgeControls
            }

            controlGroup {
                playerButton(
                    systemName: "scope",
                    accessibilityLabel: "Choose start paragraph",
                    isActive: isSelectingStart,
                    action: onToggleStartSelection
                )

                playerButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    accessibilityLabel: isPaused ? "Resume" : "Pause",
                    isProminent: true,
                    action: onTogglePause
                )

                playerButton(
                    systemName: "forward.end.fill",
                    accessibilityLabel: "Next line",
                    action: onSkip
                )
            }

            controlGroup {
                speedMenu
                pauseMenu
            }

            controlGroup {
                playerButton(
                    systemName: "xmark",
                    accessibilityLabel: "Close player",
                    tint: .secondary,
                    action: onClose
                )
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.48), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var statusCluster: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(characterName ?? "Voice Over")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                if isSelectingStart {
                    Label("Pick start", systemImage: "scope")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            }

            Text(statusDetailText)
                .font(.caption)
                .foregroundStyle(statusDetailColor)
                .lineLimit(1)
        }
    }

    private var pauseNudgeControls: some View {
        HStack(spacing: 6) {
            playerButton(
                systemName: "minus",
                accessibilityLabel: "Shorten pause",
                size: 34,
                action: { onAdjustPause(-0.75) }
            )

            playerButton(
                systemName: "plus",
                accessibilityLabel: "Lengthen pause",
                size: 34,
                action: { onAdjustPause(0.75) }
            )
        }
        .padding(5)
        .background(.thinMaterial, in: Capsule())
    }

    private var speedMenu: some View {
        Menu {
            ForEach(rates, id: \.value) { rate in
                Button {
                    onSelectRate(rate.value)
                } label: {
                    if selectedRate == rate.value {
                        Label(rate.label, systemImage: "checkmark")
                    } else {
                        Text(rate.label)
                    }
                }
            }
        } label: {
            Text(selectedRateLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 40)
                .background(.blue.opacity(0.10), in: Capsule())
        }
        .accessibilityLabel("Playback speed")
    }

    private var pauseMenu: some View {
        Menu {
            ForEach(pauseRates, id: \.value) { rate in
                Button {
                    onSelectPauseMultiplier(rate.value)
                } label: {
                    if selectedPauseRate == rate.value {
                        Label(rate.label, systemImage: "checkmark")
                    } else {
                        Text(rate.label)
                    }
                }
            }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(.blue.opacity(0.10), in: Circle())
        }
        .accessibilityLabel("Pause length")
    }

    private func controlGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(6)
        .background(.thinMaterial, in: Capsule())
    }

    private func playerButton(
        systemName: String,
        accessibilityLabel: String,
        size: CGFloat = 40,
        tint: Color = .blue,
        isActive: Bool = false,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isProminent ? 18 : 17, weight: .semibold))
                .foregroundStyle(buttonForeground(tint: tint, isActive: isActive, isProminent: isProminent))
                .frame(width: size, height: size)
                .background(buttonBackground(tint: tint, isActive: isActive, isProminent: isProminent), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func buttonForeground(tint: Color, isActive: Bool, isProminent: Bool) -> Color {
        if isProminent { return .white }
        if isActive { return tint }
        return tint
    }

    private func buttonBackground(tint: Color, isActive: Bool, isProminent: Bool) -> Color {
        if isProminent { return tint }
        if isActive { return tint.opacity(0.16) }
        return Color(.secondarySystemBackground)
    }

    private var selectedRate: Double {
        rates.min(by: { abs($0.value - rateMultiplier) < abs($1.value - rateMultiplier) })?.value ?? 1
    }

    private var selectedRateLabel: String {
        rates.first(where: { $0.value == selectedRate })?.label ?? "1x"
    }

    private var selectedPauseRate: Double {
        pauseRates.min(by: { abs($0.value - pauseMultiplier) < abs($1.value - pauseMultiplier) })?.value ?? 1
    }

    private var statusDetailText: String {
        if let countdownText {
            return countdownText
        }

        if isSelectingStart {
            return "Tap highlighted text to start there"
        }

        return status
    }

    private var statusDetailColor: Color {
        if countdownText != nil {
            return isNextPage ? .orange : .secondary
        }

        return isSelectingStart ? .blue : .secondary
    }

    private var countdownText: String? {
        guard let pauseRemainingSeconds else { return nil }
        let seconds = max(Int(ceil(pauseRemainingSeconds)), 0)
        return isNextPage ? "Next page in \(seconds)s" : "Next line in \(seconds)s"
    }
}

    /// Seeds the in-memory ScriptSessionState from the persisted ScriptReadingSession
    /// so the app remembers the last rehearsed character across app restarts.
    private func restoreRehearsalState() {
        let state = sessionStore.session(for: document.id)
        // Only restore when nothing is set yet (avoids stomping a fresh in-session pick)
        guard state.selectedCharacter == nil else { return }

        // Capture UUID into a plain local — required for #Predicate to work correctly
        let docID = document.id
        var descriptor = FetchDescriptor<ScriptReadingSession>(
            predicate: #Predicate { $0.documentId == docID }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]

        guard let saved = try? context.fetch(descriptor).first,
              let character = saved.selectedCharacter,
              !character.isEmpty else { return }

        state.selectedCharacter = character
    }

    private func autoOpenPracticeIfNeeded() {
        guard !hasAutoOpenedPractice,
              initialPracticeTurnSequenceIndex != nil,
              let parseResult = vm.parseResult,
              !parseResult.dialogueTurns.isEmpty else { return }

        hasAutoOpenedPractice = true
        isShowingPractice = true
    }

    /// Characters with at least one letter — filters out parser false-positives like "2." or "IV."
    private var filteredCharacters: [ScriptCharacter] {
        (vm.parseResult?.characters ?? []).filter { c in
            c.name.count >= 2 && c.name.contains(where: { $0.isLetter })
        }
    }

    private var fileMissingPlaceholder: some View {
        ContentUnavailableView {
            Label("PDF Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text(AppError.fileMissing.localizedDescription)
        }
    }

    // MARK: - Sidebar content

    private var sidebarContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ReaderSidebarHeaderCard(
                    title: document.title,
                    currentPageIndex: currentPageIndex,
                    pageCount: document.pageCount,
                    currentScene: currentScene,
                    parseResult: vm.parseResult,
                    characterCount: filteredCharacters.count,
                    isParsing: vm.isParsing,
                    indexedAt: vm.indexedAt,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            columnVisibility = .detailOnly
                        }
                    }
                )

                ReaderSidebarQuickActions(
                    hasIndex: vm.parseResult?.dialogueTurns.isEmpty == false,
                    isParsing: vm.isParsing,
                    onPractice: { isShowingPractice = true },
                    onLyrics: { isShowingLyrics = true },
                    onSearch: { isShowingSearch = true },
                    onAddBookmark: {
                        bookmarkLabelDraft = ""
                        isShowingAddBookmark = true
                    },
                    onBuildIndex: {
                        Task { await vm.buildIndex(for: document, context: context, forceRebuild: true) }
                    }
                )

                ReaderSidebarSceneSection(
                    scenes: vm.parseResult?.scenes ?? [],
                    isParsing: vm.isParsing,
                    hasParseResult: vm.parseResult != nil,
                    currentSceneIndex: currentSceneIndex,
                    onJump: { vm.jumpToPage = $0 }
                )

                if !bookmarks.isEmpty {
                    ReaderSidebarBookmarkSection(
                        bookmarks: bookmarks,
                        onJump: { vm.jumpToPage = $0 },
                        onDelete: { bookmark in
                            context.delete(bookmark)
                            try? context.save()
                        }
                    )
                }

                if !filteredCharacters.isEmpty {
                    ReaderSidebarCharacterSection(
                        characters: filteredCharacters,
                        dialogueTurnCounts: dialogueTurnCounts,
                        hasParseResult: vm.parseResult != nil,
                        onJump: { vm.jumpToPage = $0 },
                        onInfo: { selectedCharacterForDetail = $0 }
                    )
                }

                if showFormatWarning {
                    ReaderSidebarWarningBanner(
                        message: "This PDF may not follow standard screenplay format. Some features may be limited."
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Current scene tracking

    private var currentScene: ScriptScene? {
        guard let scenes = vm.parseResult?.scenes, !scenes.isEmpty else { return nil }
        var result: ScriptScene? = nil
        for scene in scenes {
            if scene.startPage <= currentPageIndex {
                result = scene
            } else {
                break
            }
        }
        return result ?? scenes.first
    }

    private var currentSceneIndex: Int? {
        currentScene?.index
    }

    // MARK: Warning visibility

    private var showFormatWarning: Bool {
        guard let pr = vm.parseResult else { return false }
        return pr.scenes.isEmpty || pr.dialogueTurns.isEmpty
    }
}
