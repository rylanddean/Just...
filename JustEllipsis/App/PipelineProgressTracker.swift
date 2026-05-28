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

    func start(phase: String, total: Int) {
        self.phase = phase
        self.current = 0
        self.total = total
        self.isRunning = true
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
        if generated + skipped > 0 {
            lastSummarizeSummary = "\(generated) generated · \(skipped) skipped"
        }
    }

    func reset() {
        isRunning = false
    }
}
