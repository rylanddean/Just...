import Foundation
import AVFoundation
import MediaPlayer
import Observation
import os

/// On-device text-to-speech for Listen mode.
///
/// Speaks a stripped article one sentence at a time so the active sentence can
/// be tracked and highlighted in the reader. All synthesis is local —
/// `AVSpeechSynthesizer` never makes a network request.
@Observable
@MainActor
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {

    // MARK: Speed

    enum Speed {
        static let defaultsKey = "listen.speedMultiplier"
        /// No 2× — at 2× the voice clarity degrades too far for comprehension.
        static let options: [Float] = [0.9, 1.0, 1.25, 1.5, 1.75]
        static let defaultValue: Float = 1.0
    }

    // MARK: State

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var sentences: [String] = []
    private(set) var currentIndex: Int = 0
    var isPlaying: Bool = false

    /// Persisted playback speed multiplier (1.0 = system default rate).
    var speedMultiplier: Float {
        didSet {
            guard speedMultiplier != oldValue else { return }
            UserDefaults.standard.set(speedMultiplier, forKey: Speed.defaultsKey)
            // Apply immediately by re-speaking the current sentence onward.
            if isPlaying { speak(from: currentIndex) }
            updateNowPlaying()
        }
    }

    private var title: String = ""
    private var estimatedSeconds: Double = 0

    // Maps an enqueued utterance back to its sentence index.
    private var utteranceIndex: [ObjectIdentifier: Int] = [:]

    private static let log = Logger(subsystem: "com.rylandean.justellipsis", category: "SpeechPlayer")

    override init() {
        let stored = UserDefaults.standard.object(forKey: Speed.defaultsKey) as? Float
        speedMultiplier = stored ?? Speed.defaultValue
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Loading

    func load(sentences: [String], title: String, estimatedMinutes: Int) {
        self.sentences = sentences
        self.title = title
        self.estimatedSeconds = Double(estimatedMinutes) * 60
        currentIndex = 0
        isPlaying = false
    }

    // MARK: - Transport

    func play() {
        guard !sentences.isEmpty else { return }
        configureAudioSession()
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
        } else if !synthesizer.isSpeaking {
            speak(from: currentIndex)
        }
        registerRemoteCommands()
        updateNowPlaying()
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Rewind roughly 10 seconds of speech, then continue playing.
    func skipBack() {
        var remaining = 10.0
        var idx = currentIndex
        while idx > 0 && remaining > 0 {
            idx -= 1
            remaining -= estimatedDuration(of: sentences[idx])
        }
        speak(from: idx)
        updateNowPlaying()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        utteranceIndex.removeAll()
        deactivateAudioSession()
        clearNowPlaying()
    }

    // MARK: - Speaking

    private func speak(from index: Int) {
        guard sentences.indices.contains(index) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        utteranceIndex.removeAll()
        currentIndex = index

        let voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        let rate = clampedRate()

        for i in index..<sentences.count {
            let utterance = AVSpeechUtterance(string: sentences[i])
            utterance.voice = voice
            utterance.rate = rate
            utteranceIndex[ObjectIdentifier(utterance)] = i
            synthesizer.speak(utterance)
        }
        isPlaying = true
    }

    private func clampedRate() -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate * speedMultiplier
        return min(max(base, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// Rough spoken-duration estimate for a sentence, used by skip-back.
    private func estimatedDuration(of sentence: String) -> Double {
        let words = sentence.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let wordsPerSecond = 3.0 * Double(speedMultiplier)
        return max(0.6, Double(words) / wordsPerSecond)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let idx = utteranceIndex[ObjectIdentifier(utterance)] {
                currentIndex = idx
                updateNowPlaying()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let idx = utteranceIndex[ObjectIdentifier(utterance)] else { return }
            if idx >= sentences.count - 1 {
                // Reached the end of the article.
                isPlaying = false
                updateNowPlaying()
            }
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback without .mixWithOthers temporarily pauses other audio.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }

    private func deactivateAudioSession() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private nonisolated func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                // Incoming call, Siri, etc. — pause.
                if self.isPlaying { self.pause() }
            case .ended:
                let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                    AVAudioSession.InterruptionOptions(rawValue: $0)
                } ?? []
                if options.contains(.shouldResume) { self.play() }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Now Playing / remote commands

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBack() }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Just…",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speedMultiplier) : 0.0
        ]
        if estimatedSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = estimatedSeconds
            let fraction = sentences.isEmpty ? 0 : Double(currentIndex) / Double(sentences.count)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = estimatedSeconds * fraction
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
    }
}
