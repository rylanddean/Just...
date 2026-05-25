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
    var feedDescription: String?
    var summary: String?
    var estimatedReadingMinutes: Int?
    var isEpisode: Bool = false
    var transcriptURL: String?
    var transcriptFormatRaw: String?

    init(feedID: UUID, url: String, title: String, publishedAt: Date,
         feedDescription: String? = nil, isEpisode: Bool = false,
         transcriptURL: String? = nil, transcriptFormatRaw: String? = nil) {
        self.feedID = feedID
        self.url = url
        self.title = title
        self.publishedAt = publishedAt
        self.feedDescription = feedDescription
        self.isEpisode = isEpisode
        self.transcriptURL = transcriptURL
        self.transcriptFormatRaw = transcriptFormatRaw
    }
}
