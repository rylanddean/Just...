import SwiftData
import Foundation

enum FeedType: String, Codable {
    case rss
    case scraped
    case newsletter
}

@Model
final class RSSFeed {
    var id: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var category: String = ""
    var lastFetchedAt: Date?
    var isPaused: Bool = false
    var feedTypeRaw: String = FeedType.rss.rawValue
    // Non-nil for .newsletter feeds — the Kill the Newsletter reading address
    var newsletterEmail: String? = nil

    var feedType: FeedType {
        get { FeedType(rawValue: feedTypeRaw) ?? .rss }
        set { feedTypeRaw = newValue.rawValue }
    }

    init(url: String, title: String, category: String) {
        self.url = url
        self.title = title
        self.category = category
    }
}
