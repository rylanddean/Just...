import Foundation

struct AddLinkIntent {
    static func addLink(url: URL) {
        PendingLinkStore.append(urlString: url.absoluteString)
    }
}
