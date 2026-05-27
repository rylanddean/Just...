import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ReflectViewModel {

    var text: String = ""
    var secondsRemaining: Int = 60
    var canSave: Bool = false
    var isSaved: Bool = false

    private var timer: Timer?
    private var startTime: Date = Date()

    // MARK: - Timer

    func startCountdown() {
        guard timer == nil else { return }
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.secondsRemaining > 0 {
                    self.secondsRemaining -= 1
                } else {
                    self.canSave = true
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: - Persist

    /// Returns true if the save actually ran (false if already saved — caller should ignore).
    @discardableResult
    func save(entry: BrainEntry, context: ModelContext) -> Bool {
        guard !isSaved else { return false }
        context.insert(entry)
        let reflection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = reflection.isEmpty ? nil : reflection
        entry.reflectionMode = reflection.isEmpty ? nil : "typed"
        entry.reflectionSeconds = Int(Date().timeIntervalSince(startTime))
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
        entry.reflectionSeconds = Int(Date().timeIntervalSince(startTime))
        try? context.save()
        timer?.invalidate()
        timer = nil
        isSaved = true
        return true
    }
}
