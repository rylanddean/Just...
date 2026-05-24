import Foundation

/// Lightweight handoff between the Share Extension (writer) and the main app (reader).
/// Uses App Group UserDefaults so no SwiftData types cross the module boundary.
struct PendingLinkStore {

    static let appGroupID = "group.com.rylandean.justellipsis"
    private static let key = "pendingLinks"

    /// Called by the Share Extension after the user shares a URL.
    /// Returns true if the URL was newly queued, false if it was already present.
    @discardableResult
    static func append(urlString: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        var pending = defaults.stringArray(forKey: key) ?? []
        guard !pending.contains(urlString) else { return false }
        pending.append(urlString)
        defaults.set(pending, forKey: key)
        // Force an immediate disk write — the extension process is killed as soon
        // as completeRequest fires, so in-memory UserDefaults data would be lost
        // without this call.
        defaults.synchronize()
        return true
    }

    /// Called by the main app on launch / foreground. Returns all pending URLs and clears the queue.
    static func drain() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return [] }
        let urls = defaults.stringArray(forKey: key) ?? []
        if !urls.isEmpty { defaults.removeObject(forKey: key) }
        return urls
    }
}
