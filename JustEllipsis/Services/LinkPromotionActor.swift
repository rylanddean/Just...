import Foundation
import SwiftData

/// Drains the `PendingLinkStore` UserDefaults queue into the SwiftData store.
///
/// This is the fallback path for links that couldn't be written directly from
/// the share extension (e.g. the store didn't exist yet on a fresh install).
/// Called from both the BGAppRefreshTask and `RootView` on foreground so links
/// are promoted even if the user never opens the app after sharing.
@ModelActor
actor LinkPromotionActor {

    func promotePendingLinks() {
        let urls = PendingLinkStore.drain()
        guard !urls.isEmpty else { return }

        let existing = (try? modelContext.fetch(FetchDescriptor<QueuedLink>())) ?? []
        let existingURLs = Set(existing.map { $0.url })
        let maxOrder = existing.map { $0.sortOrder }.max() ?? -1

        var added = 0
        for urlString in urls {
            guard !existingURLs.contains(urlString) else { continue }
            let link = QueuedLink(url: urlString, sortOrder: maxOrder + 1 + added)
            modelContext.insert(link)
            added += 1
        }
        if added > 0 { try? modelContext.save() }
    }
}
