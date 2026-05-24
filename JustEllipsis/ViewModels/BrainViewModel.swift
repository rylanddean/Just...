import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class BrainViewModel {

    var searchText: String = ""

    // MARK: - Rank

    func rank(for entries: [BrainEntry]) -> BrainRank {
        BrainEngine.rank(for: entries.count)
    }

    func progressToNextRank(for entries: [BrainEntry]) -> Double {
        BrainEngine.progressToNextRank(for: entries.count)
    }

    func entriesUntilNextRank(for entries: [BrainEntry]) -> Int {
        BrainEngine.entriesUntilNextRank(for: entries.count)
    }

    // MARK: - Filtering

    func filtered(_ entries: [BrainEntry]) -> [BrainEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.lowercased().contains(q)
            || entry.domain.lowercased().contains(q)
            || (entry.reflection?.lowercased().contains(q) == true)
        }
    }
}
