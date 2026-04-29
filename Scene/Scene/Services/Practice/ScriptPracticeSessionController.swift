import AVFoundation
import Combine
import Foundation

@MainActor
final class ScriptPracticeSessionController: NSObject, ObservableObject {
    @Published private(set) var currentTurn: ScriptDialogueTurn?
    @Published private(set) var spokenTurn: ScriptDialogueTurn?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var statusText = "Ready to rehearse"
    @Published private(set) var ttsUnavailable = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var playbackTask: Task<Void, Never>?
    private var speechContinuation: CheckedContinuation<Void, Never>?
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var skipToken = 0

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func start(
        turns: [ScriptDialogueTurn],
        selectedCharacter: String,
        responseWindow: TimeInterval,
        betweenTurnsPause: TimeInterval,
        speakSelectedCharacter: Bool,
        speechRate: Float = AVSpeechUtteranceDefaultSpeechRate,
        speakOtherCharacters: Bool = true,
        skippedTurnPause: TimeInterval = 0,
        showSkippedTurns: Bool = true
    ) {
        stop()
        self.speechRate = speechRate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)

        guard !selectedCharacter.isEmpty, !turns.isEmpty else {
            statusText = "No dialogue available"
            currentTurn = nil
            spokenTurn = nil
            return
        }

        isPlaying = true
        isPaused = false
        statusText = "Starting rehearsal"
        playbackTask = Task {
            await runPlayback(
                turns: turns,
                selectedCharacter: selectedCharacter,
                responseWindow: responseWindow,
                betweenTurnsPause: betweenTurnsPause,
                speakSelectedCharacter: speakSelectedCharacter,
                speakOtherCharacters: speakOtherCharacters,
                skippedTurnPause: skippedTurnPause,
                showSkippedTurns: showSkippedTurns
            )
        }
    }

    func stop() {
        skipToken += 1
        playbackTask?.cancel()
        playbackTask = nil

        // Drain the old continuation synchronously so its didCancel/didFinish
        // callback fires against a nil reference instead of accidentally resuming
        // the next task's continuation (which would skip the first spoken turn).
        let stale = speechContinuation
        speechContinuation = nil
        stale?.resume()

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        isPlaying = false
        isPaused = false
        currentTurn = nil
        spokenTurn = nil
        statusText = "Rehearsal paused"
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.pauseSpeaking(at: .word)
        }
        statusText = "Paused"
    }

    func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        if speechSynthesizer.isPaused {
            speechSynthesizer.continueSpeaking()
        }
        statusText = currentTurn?.characterName ?? "Reading"
    }

    func skipCurrentTurn() {
        guard isPlaying else { return }
        skipToken += 1
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isPaused = false
        statusText = "Skipping"
    }

    func updateSpeechRate(_ speechRate: Float) {
        self.speechRate = speechRate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
    }

    private func runPlayback(
        turns: [ScriptDialogueTurn],
        selectedCharacter: String,
        responseWindow: TimeInterval,
        betweenTurnsPause: TimeInterval,
        speakSelectedCharacter: Bool,
        speakOtherCharacters: Bool,
        skippedTurnPause: TimeInterval,
        showSkippedTurns: Bool
    ) async {
        await configureAudioSession()

        for turn in turns {
            if Task.isCancelled { return }

            let isSelectedCharacter = turn.characterName == selectedCharacter
            let shouldSpeak = isSelectedCharacter ? speakSelectedCharacter : speakOtherCharacters
            currentTurn = shouldSpeak || showSkippedTurns ? turn : nil

            if isSelectedCharacter {
                statusText = "Your line"

                if responseWindow > 0 {
                    await sleepRespectingPause(seconds: responseWindow)
                }

                if speakSelectedCharacter {
                    await speak(turn: turn, isSelectedCharacter: true)
                } else if skippedTurnPause > 0 {
                    await sleepRespectingPause(seconds: skippedTurnPause)
                }
            } else {
                statusText = turn.characterName
                if speakOtherCharacters {
                    await speak(turn: turn, isSelectedCharacter: false)
                } else if skippedTurnPause > 0 {
                    await sleepRespectingPause(seconds: skippedTurnPause)
                }
            }

            if Task.isCancelled { return }

            let pauseAfterTurn = max(betweenTurnsPause, turn.suggestedPauseAfter ?? 0)
            if pauseAfterTurn > 0 {
                await sleepRespectingPause(seconds: pauseAfterTurn)
            }
        }

        isPlaying = false
        isPaused = false
        currentTurn = nil
        spokenTurn = nil
        statusText = "Rehearsal complete"
    }

    private func configureAudioSession() async {
        #if os(iOS)
        // Check that at least one voice is available for TTS
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else {
            ttsUnavailable = true
            statusText = "Text-to-speech unavailable"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            ttsUnavailable = false
        } catch {
            ttsUnavailable = true
            statusText = "Audio session unavailable"
        }
        #endif
    }

    private func speak(turn: ScriptDialogueTurn, isSelectedCharacter: Bool) async {
        let utterance = AVSpeechUtterance(string: turn.spokenText)
        utterance.pitchMultiplier = isSelectedCharacter ? 1.08 : (turn.isVoiceOver ? 0.86 : 0.92)
        // Apply user-chosen rate; continued lines run slightly faster
        let baseRate = speechRate
        utterance.rate = turn.isContinued ? min(baseRate * 1.04, AVSpeechUtteranceMaximumSpeechRate) : baseRate
        utterance.preUtteranceDelay = turn.isOffScreen ? 0.15 : 0
        utterance.postUtteranceDelay = turn.suggestedPauseAfter ?? 0

        if let preferredLanguage = Locale.preferredLanguages.first,
           let voice = AVSpeechSynthesisVoice(language: preferredLanguage) {
            utterance.voice = voice
        }

        await withCheckedContinuation { continuation in
            speechContinuation = continuation
            spokenTurn = turn
            speechSynthesizer.speak(utterance)
        }
        spokenTurn = nil
    }

    private func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1_000_000_000)
    }

    private func sleepRespectingPause(seconds: TimeInterval) async {
        let startingSkipToken = skipToken
        var remaining = max(seconds, 0)

        while remaining > 0 {
            if Task.isCancelled || skipToken != startingSkipToken { return }

            if isPaused {
                try? await Task.sleep(nanoseconds: nanoseconds(from: 0.1))
                continue
            }

            let slice = min(remaining, 0.1)
            try? await Task.sleep(nanoseconds: nanoseconds(from: slice))
            remaining -= slice
        }
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension ScriptPracticeSessionController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            spokenTurn = nil
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            spokenTurn = nil
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }
}
