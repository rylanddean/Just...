import Foundation

@MainActor
@Observable
final class PipelineProgressTracker {

    var isRunning = false
    var phase = ""
    var current = 0
    var total = 0

    var lastTagSummary: String? = nil
    var lastSummarizeSummary: String? = nil
    var lastError: String? = nil

    private(set) var lastRunAt: Date? = nil
    private(set) var lastRunDuration: TimeInterval? = nil
    private var runStartedAt: Date? = nil

    func start(phase: String, total: Int) {
        if runStartedAt == nil { runStartedAt = Date() }
        self.phase = phase
        self.current = 0
        self.total = total
        self.isRunning = true
        self.lastError = nil
    }

    func update(current: Int) {
        self.current = current
    }

    func finishTagging(tagged: Int, fallbacks: Int, failed: Int) {
        isRunning = false
        if tagged + fallbacks + failed > 0 {
            lastTagSummary = "\(tagged) AI-tagged · \(fallbacks) fallback · \(failed) failed"
        }
    }

    func finishSummarizing(generated: Int, skipped: Int) {
        isRunning = false
        lastRunAt = Date()
        if let start = runStartedAt {
            lastRunDuration = Date().timeIntervalSince(start)
            runStartedAt = nil
        }
        if generated + skipped > 0 {
            lastSummarizeSummary = "\(generated) generated · \(skipped) skipped"
        }
    }

    func failWith(_ message: String) {
        isRunning = false
        lastError = message
        lastRunAt = Date()
        runStartedAt = nil
    }

    func reset() {
        isRunning = false
        runStartedAt = nil
    }
}
