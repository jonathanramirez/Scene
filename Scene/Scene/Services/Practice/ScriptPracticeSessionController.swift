import AVFoundation
import Combine
import Foundation

@MainActor
final class ScriptPracticeSessionController: NSObject, ObservableObject {
    @Published private(set) var currentTurn: ScriptDialogueTurn?
    @Published private(set) var isPlaying = false
    @Published private(set) var statusText = "Ready to rehearse"
    @Published private(set) var ttsUnavailable = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var playbackTask: Task<Void, Never>?
    private var speechContinuation: CheckedContinuation<Void, Never>?
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

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
        speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    ) {
        stop()
        self.speechRate = speechRate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)

        guard !selectedCharacter.isEmpty, !turns.isEmpty else {
            statusText = "No dialogue available"
            currentTurn = nil
            return
        }

        isPlaying = true
        statusText = "Starting rehearsal"
        playbackTask = Task {
            await runPlayback(
                turns: turns,
                selectedCharacter: selectedCharacter,
                responseWindow: responseWindow,
                betweenTurnsPause: betweenTurnsPause,
                speakSelectedCharacter: speakSelectedCharacter
            )
        }
    }

    func stop() {
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
        statusText = "Rehearsal paused"
    }

    private func runPlayback(
        turns: [ScriptDialogueTurn],
        selectedCharacter: String,
        responseWindow: TimeInterval,
        betweenTurnsPause: TimeInterval,
        speakSelectedCharacter: Bool
    ) async {
        await configureAudioSession()

        for turn in turns {
            if Task.isCancelled { return }

            currentTurn = turn

            if turn.characterName == selectedCharacter {
                statusText = "Your line"

                if responseWindow > 0 {
                    try? await Task.sleep(nanoseconds: nanoseconds(from: responseWindow))
                }

                if speakSelectedCharacter {
                    await speak(turn: turn, isSelectedCharacter: true)
                }
            } else {
                statusText = turn.characterName
                await speak(turn: turn, isSelectedCharacter: false)
            }

            if Task.isCancelled { return }

            let pauseAfterTurn = max(betweenTurnsPause, turn.suggestedPauseAfter ?? 0)
            if pauseAfterTurn > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds(from: pauseAfterTurn))
            }
        }

        isPlaying = false
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
            speechSynthesizer.speak(utterance)
        }
    }

    private func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1_000_000_000)
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
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }
}
