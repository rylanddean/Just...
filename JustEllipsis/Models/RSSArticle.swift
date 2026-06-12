import SwiftData
import Foundation

@Model
final class RSSArticle {
    var id: UUID = UUID()
    var feedID: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var publishedAt: Date = Date()
    var isQueued: Bool = false
    var isRead: Bool? = nil
    var isConfirmationDismissed: Bool = false
    var isSeen: Bool = false
    var feedDescription: String?
    var summary: String?
    var estimatedReadingMinutes: Int?
    var qualityGrade: ArticleQualityGrade?
    var topics: [String] = []
    var rewrittenTitle: String?

    var displayTitle: String {
        if let r = rewrittenTitle, !r.isEmpty { return r }
        return title
    }

    var hasRewrite: Bool { rewrittenTitle.map { !$0.isEmpty } ?? false }

    init(feedID: UUID, url: String, title: String, publishedAt: Date, feedDescription: String? = nil) {
        self.feedID = feedID
        self.url = url
        self.title = title
        self.publishedAt = publishedAt
        self.feedDescription = feedDescription
    }
}
