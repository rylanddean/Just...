import SwiftData
import Foundation

@Model
final class DailyEdition {
    var id: UUID
    var date: Date
    var articleURLs: [String]
    var articleTitles: [String]
    var articleDomains: [String]
    var articleFeedIDStrings: [String]
    var articleSummaries: [String]
    var currentIndex: Int
    var isComplete: Bool
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        articleURLs: [String] = [],
        articleTitles: [String] = [],
        articleDomains: [String] = [],
        articleFeedIDStrings: [String] = [],
        articleSummaries: [String] = [],
        currentIndex: Int = 0,
        isComplete: Bool = false,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.articleURLs = articleURLs
        self.articleTitles = articleTitles
        self.articleDomains = articleDomains
        self.articleFeedIDStrings = articleFeedIDStrings
        self.articleSummaries = articleSummaries
        self.currentIndex = currentIndex
        self.isComplete = isComplete
        self.generatedAt = generatedAt
    }

    var totalCount: Int { articleURLs.count }
    var articlesRead: Int { min(currentIndex, totalCount) }
    var hasStarted: Bool { currentIndex > 0 || isComplete }

    func article(at index: Int) -> (url: String, title: String, domain: String, feedID: UUID?, summary: String?)? {
        guard index < articleURLs.count else { return nil }
        let summary = articleSummaries[safe: index].flatMap { $0.isEmpty ? nil : $0 }
        return (
            articleURLs[index],
            articleTitles[index],
            articleDomains[index],
            UUID(uuidString: articleFeedIDStrings[safe: index] ?? ""),
            summary
        )
    }

    var currentArticle: (url: String, title: String, domain: String, feedID: UUID?, summary: String?)? {
        article(at: currentIndex)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
