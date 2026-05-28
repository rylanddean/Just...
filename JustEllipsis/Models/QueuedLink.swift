import SwiftData
import Foundation

enum PrefetchState: String {
    case pending
    case ready
    case invalid
    case retrying
}

// Stored as "manual", "rss:<feedUUID>", or "aiPick"
enum LinkSource: Equatable {
    case manual
    case rss(feedID: UUID)
    case aiPick

    var rawValue: String {
        switch self {
        case .manual: return "manual"
        case .rss(let id): return "rss:\(id.uuidString)"
        case .aiPick: return "aiPick"
        }
    }

    init(rawValue: String) {
        if rawValue == "aiPick" {
            self = .aiPick
        } else if rawValue.hasPrefix("rss:"),
                  let id = UUID(uuidString: String(rawValue.dropFirst(4))) {
            self = .rss(feedID: id)
        } else {
            self = .manual
        }
    }

    var isRSSPick: Bool {
        switch self {
        case .rss, .aiPick: return true
        case .manual: return false
        }
    }
}

@Model
final class QueuedLink {
    var id: UUID = UUID()
    var url: String = ""
    var title: String?
    var domain: String?
    var addedAt: Date = Date()
    var sortOrder: Int = 0
    var isRead: Bool = false
    @Attribute(.externalStorage) var cachedHTML: String?
    var prefetchStateRaw: String = PrefetchState.pending.rawValue
    var sourceRaw: String = "manual"
    var threadSourceURL: String?

    var prefetchState: PrefetchState {
        get { PrefetchState(rawValue: prefetchStateRaw) ?? .pending }
        set { prefetchStateRaw = newValue.rawValue }
    }

    var source: LinkSource {
        get { LinkSource(rawValue: sourceRaw) }
        set { sourceRaw = newValue.rawValue }
    }

    init(url: String, sortOrder: Int, title: String? = nil, domain: String? = nil, source: LinkSource = .manual, threadSourceURL: String? = nil) {
        self.url = url
        self.sortOrder = sortOrder
        self.title = title
        self.domain = domain
        self.sourceRaw = source.rawValue
        self.threadSourceURL = threadSourceURL
    }
}
