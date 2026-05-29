import Foundation
import SwiftData

enum SaveResult {
    case saved
    case duplicate
}

struct AddLinkIntent {

    /// Saves a shared URL into the app's SwiftData store.
    ///
    /// Primary path: writes a `QueuedLink` directly to the shared SQLite store in
    /// the App Group container. Because the store already contains the record when
    /// the main app next runs (even via a background task), NSPersistentCloudKitContainer
    /// can push it to CloudKit without requiring the user to foreground the app.
    ///
    /// Fallback: if the store isn't accessible yet (e.g. fresh install where the
    /// main app has never launched), the URL is written to the App Group UserDefaults
    /// so `RootView.processPendingLinks()` can drain it on first launch.
    static func addLink(url: URL) -> SaveResult {
        if let result = writeToSwiftDataStore(url: url) { return result }
        return PendingLinkStore.append(urlString: url.absoluteString) ? .saved : .duplicate
    }

    // MARK: - Direct SwiftData write

    private static func writeToSwiftDataStore(url: URL) -> SaveResult? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PendingLinkStore.appGroupID
        ) else { return nil }

        let storeURL = groupURL.appendingPathComponent("JustEllipsis.store")

        // If the store doesn't exist the main app has never launched — fall back
        // to the UserDefaults path so the record isn't lost.
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }

        do {
            // Open without CloudKit — extensions cannot use NSPersistentCloudKitContainer.
            // The main app's NSPersistentCloudKitContainer will detect the new, unsynced
            // row on its next sync cycle and export it to iCloud automatically.
            let schema = Schema([QueuedLink.self, BrainEntry.self, ReadingDay.self, RSSFeed.self])
            let config = ModelConfiguration(
                "main",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)

            // Duplicate check
            let urlString = url.absoluteString
            let matches = try ctx.fetch(FetchDescriptor<QueuedLink>(
                predicate: #Predicate { $0.url == urlString }
            ))
            guard matches.isEmpty else { return .duplicate }

            // Determine sort order (append after the current last item)
            let all = try ctx.fetch(FetchDescriptor<QueuedLink>(
                sortBy: [SortDescriptor(\QueuedLink.sortOrder, order: .reverse)]
            ))
            let nextOrder = (all.first?.sortOrder ?? -1) + 1

            let link = QueuedLink(url: urlString, sortOrder: nextOrder)
            ctx.insert(link)
            try ctx.save()
            return .saved
        } catch {
            // Anything goes wrong (schema migration, file lock, etc.) — fall through
            // to the UserDefaults path rather than showing an error to the user.
            return nil
        }
    }
}
