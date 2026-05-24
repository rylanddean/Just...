import Foundation
import SwiftData
import Observation
import os

private let logger = Logger(subsystem: "com.rylandean.justellipsis", category: "Reflect")

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
        logger.debug("save() called — isSaved=\(self.isSaved), textLength=\(self.text.count)")
        guard !isSaved else {
            logger.warning("save() guard tripped — isSaved already true, returning false")
            return false
        }
        logger.debug("inserting entry into context")
        context.insert(entry)
        let reflection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = reflection.isEmpty ? nil : reflection
        entry.reflectionMode = reflection.isEmpty ? nil : mode.rawValue
        entry.reflectionSeconds = secondsSpent
        logger.debug("calling context.save()")
        do {
            try context.save()
            logger.debug("context.save() succeeded")
        } catch {
            logger.error("context.save() FAILED: \(error)")
        }
        timer?.invalidate()
        timer = nil
        isSaved = true
        logger.debug("save() complete — returning true")
        return true
    }

    /// Returns true if the skip actually ran (false if already saved — caller should ignore).
    @discardableResult
    func skip(entry: BrainEntry, context: ModelContext) -> Bool {
        logger.debug("skip() called — isSaved=\(self.isSaved)")
        guard !isSaved else {
            logger.warning("skip() guard tripped — isSaved already true, returning false")
            return false
        }
        context.insert(entry)
        entry.reflection = nil
        entry.reflectionMode = nil
        entry.reflectionSeconds = 60 - secondsRemaining
        do {
            try context.save()
            logger.debug("skip context.save() succeeded")
        } catch {
            logger.error("skip context.save() FAILED: \(error)")
        }
        timer?.invalidate()
        timer = nil
        isSaved = true
        logger.debug("skip() complete — returning true")
        return true
    }
}
