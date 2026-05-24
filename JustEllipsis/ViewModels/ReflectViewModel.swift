import Foundation
import SwiftData
import Observation

enum ReflectionMode: String {
    case typed = "typed"
    case voice = "voice"
}

@Observable
@MainActor
final class ReflectViewModel {

    var text: String = ""
    var secondsRemaining: Int = 60
    var isTyping: Bool = false
    var isSaved: Bool = false

    private var timer: Timer?
    private var isPaused: Bool = false

    // MARK: - Timer

    func startCountdown() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isPaused else { return }
                if self.secondsRemaining > 0 {
                    self.secondsRemaining -= 1
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func pauseCountdown() {
        isPaused = true
    }

    func resumeCountdown() {
        isPaused = false
    }

    // MARK: - Persist

    /// Returns true if the save actually ran (false if already saved — caller should ignore).
    @discardableResult
    func save(
        entry: BrainEntry,
        mode: ReflectionMode,
        secondsSpent: Int,
        context: ModelContext
    ) -> Bool {
        guard !isSaved else { return false }
        // Insert into the context BEFORE writing properties. SwiftData has a known
        // iOS 17 issue where values written to the unmanaged backing store are
        // silently dropped when the object is later handed to the context.
        context.insert(entry)
        let reflection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = reflection.isEmpty ? nil : reflection
        entry.reflectionMode = reflection.isEmpty ? nil : mode.rawValue
        entry.reflectionSeconds = secondsSpent
        try? context.save()
        timer?.invalidate()
        timer = nil
        isSaved = true
        return true
    }

    /// Returns true if the skip actually ran (false if already saved — caller should ignore).
    @discardableResult
    func skip(entry: BrainEntry, context: ModelContext) -> Bool {
        guard !isSaved else { return false }
        context.insert(entry)
        entry.reflection = nil
        entry.reflectionMode = nil
        entry.reflectionSeconds = 60 - secondsRemaining
        try? context.save()
        timer?.invalidate()
        timer = nil
        isSaved = true
        return true
    }
}
