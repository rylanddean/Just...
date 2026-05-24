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

    func save(
        entry: BrainEntry,
        mode: ReflectionMode,
        secondsSpent: Int,
        context: ModelContext
    ) {
        guard !isSaved else { return }
        let reflection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = reflection.isEmpty ? nil : reflection
        entry.reflectionMode = reflection.isEmpty ? nil : mode.rawValue
        entry.reflectionSeconds = secondsSpent
        persistEntry(entry, context: context)
    }

    func skip(entry: BrainEntry, context: ModelContext) {
        guard !isSaved else { return }
        entry.reflection = nil
        entry.reflectionMode = nil
        entry.reflectionSeconds = 60 - secondsRemaining
        persistEntry(entry, context: context)
    }

    private func persistEntry(_ entry: BrainEntry, context: ModelContext) {
        context.insert(entry)
        try? context.save()
        timer?.invalidate()
        timer = nil
        isSaved = true
    }
}
