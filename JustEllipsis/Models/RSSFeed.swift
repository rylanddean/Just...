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
    // Set when the user completes reading an article from this feed
    var lastReadAt: Date? = nil
    // Set to the most recent publishedAt when new articles are stored for this feed
    var lastArticleAt: Date? = nil
    // Archive state — archived feeds are hidden from the active list and skipped during fetch
    var isArchived: Bool = false
    // "unread:7", "dead:14", or "manual" — parsed in views for display
    var archiveReason: String? = nil
    var isFavourite: Bool = false

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
