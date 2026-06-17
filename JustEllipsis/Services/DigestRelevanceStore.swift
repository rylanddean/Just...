import Foundation

@Observable
@MainActor
final class DigestRelevanceStore {
    var scores: [UUID: Double] = [:]

    func score(for id: UUID) -> Double { scores[id] ?? 0 }

    func computeScores(for articles: [RSSArticle], concepts: [String]) {
        guard !concepts.isEmpty else { return }
        for article in articles where scores[article.id] == nil {
            scores[article.id] = IntelligenceService.scoreRelevance(
                title: article.displayTitle,
                concepts: concepts
            )
        }
    }
}
