import Foundation

@MainActor
@Observable
final class GradingProgressTracker {
    var activeIDs: Set<UUID> = []
    var isRunning: Bool = false
    var lastError: String? = nil

    func markActive(_ id: UUID) {
        activeIDs.insert(id)
        isRunning = true
        lastError = nil
    }

    func markDone(_ id: UUID) { activeIDs.remove(id) }

    func markFinished() {
        activeIDs.removeAll()
        isRunning = false
    }

    func markCancelled(graded: Int, remaining: Int) {
        activeIDs.removeAll()
        isRunning = false
        if remaining > 0 {
            lastError = "Grading paused — \(remaining) articles remaining. Tap to resume."
        }
    }

    func markFailed() {
        activeIDs.removeAll()
        isRunning = false
        lastError = "Grading stopped. Apple Intelligence may be unavailable."
    }

    func reset() {
        activeIDs.removeAll()
        isRunning = false
    }
}
