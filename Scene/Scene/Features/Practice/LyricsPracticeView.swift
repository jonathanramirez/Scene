import AVFoundation
import SwiftData
import SwiftUI

struct LyricsPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ScriptSessionStore.self) private var sessionStore

    let document: ScriptDocument
    let parseResult: ScriptParseResult

    @StateObject private var controller = ScriptPracticeSessionController()

    // Appearance (shared with LyricsSettingsView via AppStorage)
    @AppStorage("lyricsIsDarkMode")   private var isDarkMode   = true
    @AppStorage("lyricsFontSizeStep") private var fontSizeStep: Int = 0

    // Setup phase
    @State private var setupComplete = false
    @State private var selectedCharacter = ""
    @State private var hideMyLines = true
    @State private var speakMyLines = false
    @State private var responseWindow: Double = 4
    @State private var betweenTurnsPause: Double = 0.8
    @State private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

    // Lyrics phase
    @State private var revealCurrentLine = false
    @State private var tappedTurnID: UUID?
    @State private var isShowingAppearance = false
    @State private var isShowingPractice = false

    private var session: ScriptSessionState { sessionStore.session(for: document.id) }

    var body: some View {
        if setupComplete {
            lyricsStage
        } else {
            setupStage
        }
    }

    // MARK: - Setup

    private var setupStage: some View {
        NavigationStack {
            Form {
                Section("Your Character") {
                    Picker("Role", selection: $selectedCharacter) {
                        ForEach(availableCharacters, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if !selectedCharacter.isEmpty {
                        let count = parseResult.dialogueTurns.filter { $0.characterName == selectedCharacter }.count
                        Text("\(count) dialogue turns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Playback") {
                    Toggle("Hide my lines (memory mode)", isOn: $hideMyLines)
                    Toggle("Read my lines aloud", isOn: $speakMyLines)
                    Stepper(
                        "My line window: \(responseWindow.formatted(.number.precision(.fractionLength(1))))s",
                        value: $responseWindow, in: 1...12, step: 0.5
                    )
                    Stepper(
                        "Between turns: \(betweenTurnsPause.formatted(.number.precision(.fractionLength(1))))s",
                        value: $betweenTurnsPause, in: 0...4, step: 0.2
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading speed: \(lyricsSpeedLabel(speechRate))")
                            .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { Double(speechRate) },
                                set: { speechRate = Float($0) }
                            ),
                            in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)
                        )
                        .tint(.orange)
                    }
                }

                if controller.ttsUnavailable {
                    Section {
                        Label("Text-to-speech unavailable. Lyrics will scroll but won't be read aloud.", systemImage: "speaker.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Start Lyrics Mode") {
                        setupComplete = true
                        startPlayback()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCharacter.isEmpty || parseResult.dialogueTurns.isEmpty)
                }
            }
            .navigationTitle("Lyrics Mode")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAppearance = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                }
            }
        }
        .onAppear {
            speechRate = session.speechRate
            if let savedChar = session.selectedCharacter, availableCharacters.contains(savedChar) {
                selectedCharacter = savedChar
                hideMyLines = session.memoryMode
                speakMyLines = session.readAloudEnabled
                // Skip setup if coming from Practice
                setupComplete = true
                startPlaybackFromSession()
            } else if selectedCharacter.isEmpty {
                selectedCharacter = availableCharacters.first ?? ""
            }
        }
        .sheet(isPresented: $isShowingAppearance) {
            LyricsSettingsView()
        }
    }

    // MARK: - Lyrics Stage

    private var lyricsStage: some View {
        ZStack(alignment: .bottom) {
            bgColor.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 220)

                        ForEach(parseResult.dialogueTurns) { turn in
                            lyricsTurnRow(turn: turn)
                                .id(turn.id)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                        }

                        Color.clear.frame(height: 220)
                    }
                }
                .onChange(of: controller.currentTurn?.id) { _, newID in
                    revealCurrentLine = false
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(newID, anchor: UnitPoint(x: 0.5, y: 0.3))
                    }
                }
            }

            bottomControls
        }
        .ignoresSafeArea(edges: .bottom)
        .onDisappear { controller.stop() }
        .onChange(of: selectedCharacter) { _, v in
            session.selectedCharacter = v
            ReadingSessionService.updateRehearsal(
                documentId: document.id,
                selectedCharacter: v,
                lastMode: "lyrics",
                in: modelContext
            )
        }
        .onChange(of: hideMyLines) { _, v in session.memoryMode = v }
        .onChange(of: speakMyLines) { _, v in session.readAloudEnabled = v }
        .onChange(of: controller.currentTurn?.sequenceIndex ?? -1) { _, _ in
            session.currentTurnIndex = controller.currentTurn?.sequenceIndex
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .sheet(isPresented: $isShowingAppearance) {
            LyricsSettingsView()
        }
        .sheet(isPresented: $isShowingPractice) {
            PracticeSessionView(
                document: document,
                parseResult: parseResult,
                initialFocusedTurnSequenceIndex: controller.currentTurn?.sequenceIndex
            )
        }
    }

    // MARK: - Turn Row

    @ViewBuilder
    private func lyricsTurnRow(turn: ScriptDialogueTurn) -> some View {
        let isActive = controller.currentTurn?.id == turn.id
        let isMyTurn = turn.characterName == selectedCharacter
        let isPast   = isPast(turn: turn)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isMyTurn && isActive {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                }
                Text(turn.characterName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1.0)
                    .foregroundStyle(LyricsColors.charName(isDark: isDarkMode, isActive: isActive, isMe: isMyTurn, isPast: isPast))

                if let qualifier = turn.qualifierSummary {
                    Text(qualifier)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(isDarkMode ? 0.25 : 0.0))
                }
            }

            if let parenthetical = turn.parenthetical, !parenthetical.isEmpty {
                Text(parenthetical)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(
                        isDarkMode
                            ? Color.white.opacity(isPast ? 0.12 : (isActive ? 0.65 : 0.30))
                            : LyricsColors.readText.opacity(isPast ? 0.15 : (isActive ? 0.70 : 0.40))
                    )
            }

            dialogueContent(for: turn, isActive: isActive, isMyTurn: isMyTurn, isPast: isPast)
        }
        .scaleEffect(isActive ? 1.0 : 0.88, anchor: .leading)
        .opacity(tappedTurnID == turn.id ? 0.45 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
        .animation(.easeOut(duration: 0.25), value: tappedTurnID)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(on: turn)
        }
    }

    @ViewBuilder
    private func dialogueContent(
        for turn: ScriptDialogueTurn,
        isActive: Bool,
        isMyTurn: Bool,
        isPast: Bool
    ) -> some View {
        let offset = CGFloat(fontSizeStep) * 2

        if isMyTurn && hideMyLines && !revealCurrentLine {
            if isActive {
                Text("Tap to reveal your line")
                    .font(.system(size: 20 + offset))
                    .fontWeight(.medium)
                    .italic()
                    .foregroundStyle(LyricsColors.revealHint(isDark: isDarkMode))
                    .multilineTextAlignment(.leading)
            } else {
                Text("— — —")
                    .font(.system(size: (isPast ? 14 : 18) + offset))
                    .foregroundStyle(LyricsColors.hiddenLine(isDark: isDarkMode, isPast: isPast))
            }
        } else {
            Text(turn.dialogue)
                .font(.system(size: (isActive ? 22 : (isPast ? 16 : 20)) + offset))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(LyricsColors.dialogue(isDark: isDarkMode, isActive: isActive, isMe: isMyTurn, isPast: isPast))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.3), value: isActive)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(LyricsColors.control(isDark: isDarkMode).opacity(0.7))
                .padding(.bottom, 8)

            HStack {
                Button {
                    controller.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(LyricsColors.control(isDark: isDarkMode))
                        .symbolRenderingMode(.hierarchical)
                }

                Spacer()

                Button {
                    if controller.isPlaying { controller.stop() } else { startPlayback() }
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 62))
                        .foregroundStyle(controller.isPlaying ? LyricsColors.control(isDark: isDarkMode) : .orange)
                        .symbolRenderingMode(.hierarchical)
                }

                Spacer()

                HStack(spacing: 20) {
                    if hideMyLines {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { revealCurrentLine.toggle() }
                        } label: {
                            Image(systemName: revealCurrentLine ? "eye.slash.fill" : "eye.fill")
                                .font(.title)
                                .foregroundStyle(revealCurrentLine ? Color.orange : LyricsColors.control(isDark: isDarkMode))
                        }
                    }

                    Button {
                        session.selectedCharacter = selectedCharacter
                        session.currentTurnIndex = controller.currentTurn?.sequenceIndex
                        session.memoryMode = hideMyLines
                        session.readAloudEnabled = speakMyLines
                        isShowingPractice = true
                    } label: {
                        Image(systemName: "mic")
                            .font(.title2)
                            .foregroundStyle(LyricsColors.control(isDark: isDarkMode))
                    }

                    Button {
                        isShowingAppearance = true
                    } label: {
                        Image(systemName: "textformat.size")
                            .font(.title2)
                            .foregroundStyle(LyricsColors.control(isDark: isDarkMode))
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .padding(.bottom, 8)
        }
        .background(LyricsColors.bottomGradient(isDark: isDarkMode).ignoresSafeArea())
    }

    // MARK: - Helpers

    private var bgColor: Color {
        isDarkMode ? .black : LyricsColors.readBg
    }

    private var fontOffset: CGFloat { CGFloat(fontSizeStep) * 2 }

    private func isPast(turn: ScriptDialogueTurn) -> Bool {
        guard let currentTurn = controller.currentTurn else { return false }
        return turn.sequenceIndex < currentTurn.sequenceIndex
    }

    private func handleTap(on turn: ScriptDialogueTurn) {
        let isActive = controller.currentTurn?.id == turn.id
        let isMyTurn = turn.characterName == selectedCharacter

        if isActive && isMyTurn && hideMyLines && !revealCurrentLine {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { revealCurrentLine = true }
            return
        }

        flashTap(id: turn.id)
        startFrom(turn: turn)
    }

    private func flashTap(id: UUID) {
        tappedTurnID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            tappedTurnID = nil
        }
    }

    private func startFrom(turn: ScriptDialogueTurn) {
        guard let index = parseResult.dialogueTurns.firstIndex(where: { $0.id == turn.id }) else { return }
        let slice = Array(parseResult.dialogueTurns[index...])
        controller.start(
            turns: slice,
            selectedCharacter: selectedCharacter,
            responseWindow: responseWindow,
            betweenTurnsPause: betweenTurnsPause,
            speakSelectedCharacter: speakMyLines,
            speechRate: speechRate
        )
    }

    private func startPlayback() {
        controller.start(
            turns: parseResult.dialogueTurns,
            selectedCharacter: selectedCharacter,
            responseWindow: responseWindow,
            betweenTurnsPause: betweenTurnsPause,
            speakSelectedCharacter: speakMyLines
        )
    }

    private func startPlaybackFromSession() {
        let turns: [ScriptDialogueTurn]
        if let idx = session.currentTurnIndex,
           let startIndex = parseResult.dialogueTurns.firstIndex(where: { $0.sequenceIndex == idx }) {
            turns = Array(parseResult.dialogueTurns[startIndex...])
        } else {
            turns = parseResult.dialogueTurns
        }
        controller.start(
            turns: turns,
            selectedCharacter: selectedCharacter,
            responseWindow: responseWindow,
            betweenTurnsPause: betweenTurnsPause,
            speakSelectedCharacter: speakMyLines
        )
    }

    private func lyricsSpeedLabel(_ rate: Float) -> String {
        switch rate {
        case ..<0.25: return "Slow"
        case 0.25..<0.45: return "Normal"
        case 0.45..<0.6: return "Fast"
        default: return "Very fast"
        }
    }

    private var availableCharacters: [String] {
        let hasDialogue = Set(parseResult.dialogueTurns.map(\.characterName))
        return parseResult.characters.map(\.name).filter { hasDialogue.contains($0) }
    }
}
