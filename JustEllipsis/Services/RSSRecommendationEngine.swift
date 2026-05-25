import Foundation
import SwiftData

// MARK: - Sendable snapshots (cross actor isolation safely)

struct ArticleSnapshot: Sendable {
    let persistentModelID: PersistentIdentifier
    let url: String
    let title: String
    let feedID: UUID
    let publishedAt: Date
}

struct BrainSnapshot: Sendable {
    let title: String
    let reflection: String?
}

// MARK: - Recommendation engine

struct RSSRecommendationEngine {

    // Entry point — accepts and returns only Sendable value types.
    // Caller re-fetches originals by persistentModelID to mark isQueued.
    static func makePicks(
        freshArticles: [ArticleSnapshot],
        brainEntries: [BrainSnapshot],
        existingQueueURLs: Set<String>
    ) async -> [ArticleSnapshot] {
        let candidates = freshArticles.filter { !existingQueueURLs.contains($0.url) }
        guard !candidates.isEmpty else { return [] }

        if brainEntries.count < 5 {
            return coldStartPicks(from: candidates)
        }

        if IntelligenceService.isAvailable {
            if #available(iOS 26, *) {
                return await aiPicks(candidates: candidates, brainEntries: brainEntries)
            }
        }

        return recencyFallbackPicks(from: candidates)
    }

    // MARK: - AI picks (iOS 26+, Apple Intelligence available)

    // Lightweight Sendable snapshot for crossing task-group boundaries.
    private struct CandidateSnapshot: Sendable {
        let index: Int
        let title: String
    }

    private struct ScoredIndex: Sendable {
        let index: Int
        let score: Int
    }

    @available(iOS 26, *)
    private static func aiPicks(
        candidates: [ArticleSnapshot],
        brainEntries: [BrainSnapshot]
    ) async -> [ArticleSnapshot] {
        let profile = buildReaderProfile(from: brainEntries)

        let scored: [ScoredIndex] = await withTaskGroup(of: ScoredIndex.self) { group in
            for (i, snap) in candidates.prefix(60).enumerated() {
                let title = snap.title
                group.addTask {
                    let score = await IntelligenceService.scoreRelevance(
                        articleTitle: title,
                        readerProfile: profile
                    )
                    return ScoredIndex(index: i, score: score)
                }
            }
            var results: [ScoredIndex] = []
            for await si in group { results.append(si) }
            return results
        }

        let sorted = scored
            .filter { $0.score >= 6 }
            .sorted { $0.score > $1.score }
            .map { candidates[$0.index] }

        return diversify(sorted, maxPicks: 3)
    }

    // MARK: - Recency fallback (no AI)

    private static func recencyFallbackPicks(from candidates: [ArticleSnapshot]) -> [ArticleSnapshot] {
        var byFeed: [UUID: [ArticleSnapshot]] = [:]
        for article in candidates { byFeed[article.feedID, default: []].append(article) }

        let sortedFeeds = byFeed
            .sorted { a, b in
                (a.value.max(by: { $0.publishedAt < $1.publishedAt })?.publishedAt ?? .distantPast)
                > (b.value.max(by: { $0.publishedAt < $1.publishedAt })?.publishedAt ?? .distantPast)
            }
            .prefix(3)

        return sortedFeeds.compactMap { _, articles in
            articles.max(by: { $0.publishedAt < $1.publishedAt })
        }
    }

    // MARK: - Cold-start (Brain has <5 entries)

    private static func coldStartPicks(from candidates: [ArticleSnapshot]) -> [ArticleSnapshot] {
        let sorted = candidates.sorted { $0.publishedAt > $1.publishedAt }
        return diversify(sorted, maxPicks: 3)
    }

    // MARK: - Helpers

    private static func buildReaderProfile(from entries: [BrainSnapshot]) -> String {
        entries.prefix(30)
            .map { snap in
                var parts = [snap.title]
                if let reflection = snap.reflection, !reflection.isEmpty { parts.append(reflection) }
                return parts.joined(separator: ": ")
            }
            .joined(separator: "\n")
    }

    private static func diversify(_ articles: [ArticleSnapshot], maxPicks: Int) -> [ArticleSnapshot] {
        var seen = Set<UUID>()
        var picks: [ArticleSnapshot] = []
        for article in articles {
            guard picks.count < maxPicks else { break }
            if seen.insert(article.feedID).inserted { picks.append(article) }
        }
        return picks
    }
}

