import Foundation
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceRecognizer {

    var transcript: String = ""
    var isListening: Bool = false
    var isAvailable: Bool = false

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init() {
        isAvailable = Self.deviceSupportsOnDeviceRecognition()
    }

    // MARK: - Device Check

    nonisolated static func deviceSupportsOnDeviceRecognition() -> Bool {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        return recognizer?.supportsOnDeviceRecognition == true
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            isAvailable = false
            return false
        }

        let micStatus = await AVAudioApplication.requestRecordPermission()
        if !micStatus { isAvailable = false }
        return micStatus
    }

    // MARK: - Listening

    func startListening() throws {
        stopListening()
        transcript = ""

        let rec = SFSpeechRecognizer(locale: Locale.current)
        recognizer = rec

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        engine.prepare()
        try engine.start()

        recognitionTask = rec?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stopListening() }
            }
        }

        isListening = true
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func reset() {
        stopListening()
        transcript = ""
    }
}
