import Foundation

enum SaveResult {
    case saved
    case duplicate
}

struct AddLinkIntent {
    static func addLink(url: URL) -> SaveResult {
        PendingLinkStore.append(urlString: url.absoluteString) ? .saved : .duplicate
    }
}
