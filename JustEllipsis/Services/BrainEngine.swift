import Foundation

enum BrainRank: String, CaseIterable, Sendable {
    case curious  = "Curious"
    case reader   = "Reader"
    case thinker  = "Thinker"
    case scholar  = "Scholar"
    case polymath = "Polymath"
    case luminary = "Luminary"

    var threshold: Int {
        switch self {
        case .curious:  return 0
        case .reader:   return 26
        case .thinker:  return 101
        case .scholar:  return 301
        case .polymath: return 751
        case .luminary: return 2001
        }
    }

    var nextThreshold: Int? {
        let all = BrainRank.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1].threshold
    }
}

struct BrainEngine: Sendable {

    static func rank(for entryCount: Int) -> BrainRank {
        BrainRank.allCases.reversed().first { entryCount >= $0.threshold } ?? .curious
    }

    static func nextRankThreshold(for entryCount: Int) -> Int? {
        rank(for: entryCount).nextThreshold
    }

    static func entriesUntilNextRank(for entryCount: Int) -> Int {
        guard let next = nextRankThreshold(for: entryCount) else { return 0 }
        return max(0, next - entryCount)
    }

    /// 0.0–1.0 progress within the current rank band. Returns 1.0 at max rank.
    static func progressToNextRank(for entryCount: Int) -> Double {
        let current = rank(for: entryCount)
        guard let nextThreshold = current.nextThreshold else { return 1.0 }
        let bandSize = Double(nextThreshold - current.threshold)
        let inBand   = Double(entryCount - current.threshold)
        return min(1.0, max(0.0, inBand / bandSize))
    }
}
