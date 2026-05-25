import SwiftData
import Foundation

@Model
final class RSSArticle {
    var id: UUID = UUID()
    var feedID: UUID
    var url: String
    var title: String
    var publishedAt: Date
    var isQueued: Bool = false
    var feedDescription: String?
    var summary: String?

    init(feedID: UUID, url: String, title: String, publishedAt: Date, feedDescription: String? = nil) {
        self.feedID = feedID
        self.url = url
        self.title = title
        self.publishedAt = publishedAt
        self.feedDescription = feedDescription
    }
}
