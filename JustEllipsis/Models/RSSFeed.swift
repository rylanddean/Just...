import SwiftData
import Foundation

@Model
final class RSSFeed {
    var id: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var category: String = ""
    var lastFetchedAt: Date?
    var isPaused: Bool = false
    var feedType: FeedType = FeedType.article

    init(url: String, title: String, category: String, feedType: FeedType = .article) {
        self.url = url
        self.title = title
        self.category = category
        self.feedType = feedType
    }
}
