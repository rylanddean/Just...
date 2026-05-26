import Foundation

@MainActor
@Observable
final class GradingProgressTracker {
    var activeIDs: Set<UUID> = []

    func markActive(_ id: UUID) { activeIDs.insert(id) }
    func markDone(_ id: UUID)   { activeIDs.remove(id) }
}
