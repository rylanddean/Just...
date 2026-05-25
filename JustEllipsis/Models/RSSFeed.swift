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

    init(url: String, title: String, category: String) {
        self.url = url
        self.title = title
        self.category = category
    }
}
