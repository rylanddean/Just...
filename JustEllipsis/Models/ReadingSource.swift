import Foundation

enum ReadingSource {
    case queued(QueuedLink)
    case digest(url: String, title: String, domain: String, feedID: UUID?)
    case dailyEdition(url: String, title: String, domain: String, feedID: UUID?)

    var url: String {
        switch self {
        case .queued(let link): return link.url
        case .digest(let url, _, _, _): return url
        case .dailyEdition(let url, _, _, _): return url
        }
    }
}
