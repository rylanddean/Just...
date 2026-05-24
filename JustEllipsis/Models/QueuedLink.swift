import SwiftData
import Foundation

@Model
final class QueuedLink {
    var id: UUID = UUID()
    var url: String
    var title: String?
    var domain: String?
    var addedAt: Date = Date()
    var sortOrder: Int
    var isRead: Bool = false
    var cachedHTML: String?

    init(url: String, sortOrder: Int, title: String? = nil, domain: String? = nil) {
        self.url = url
        self.sortOrder = sortOrder
        self.title = title
        self.domain = domain
    }
}
