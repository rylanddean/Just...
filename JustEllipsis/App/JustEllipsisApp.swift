import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct JustEllipsisApp: App {

    let container: ModelContainer = makeContainer()
    @State private var router = AppRouter()

    init() {
        registerRSSBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environment(router)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
        // Prefetch cached HTML for queued links
        .backgroundTask(.appRefresh(PrefetchService.backgroundTaskID)) {
            let actor = PrefetchActor(modelContainer: container)
            await actor.prefetch(max: 3)
            PrefetchService.scheduleNextBackgroundTask()
        }
    }

    // BGProcessingTask must be registered via BGTaskScheduler (SwiftUI has no .processing variant).
    private func registerRSSBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: RSSFetchService.backgroundTaskID,
            using: nil
        ) { [self] bgTask in
            guard let processingTask = bgTask as? BGProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            let taskHandle = Task {
                let actor = RSSFetchActor(modelContainer: container)
                await actor.performDailyJob()
                RSSFetchService.scheduleNextBackgroundTask()
                processingTask.setTaskCompleted(success: true)
            }
            processingTask.expirationHandler = { taskHandle.cancel() }
        }
    }

    // MARK: - URL handling

    // Handles feed:// URLs launched from Safari or tapped in other apps.
    // feed://example.com/feed.xml  →  https://example.com/feed.xml
    // feed:https://example.com/feed.xml  →  https://example.com/feed.xml
    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "feed" else { return }

        let httpsString: String
        if let host = url.host, !host.isEmpty {
            // feed://example.com/path  →  https://example.com/path
            let path = url.path.isEmpty ? "" : url.path
            let query = url.query.map { "?\($0)" } ?? ""
            httpsString = "https://\(host)\(path)\(query)"
        } else {
            // feed:https://…  →  https://…
            let raw = url.absoluteString
            let stripped = raw.hasPrefix("feed:") ? String(raw.dropFirst("feed:".count)) : raw
            httpsString = stripped
        }

        guard URL(string: httpsString)?.scheme?.hasPrefix("http") == true else { return }
        router.pendingFeedURL = httpsString
        router.selectedTab = 1 // Feeds tab
    }

    // MARK: - ModelContainer

    static let iCloudSyncKey = "iCloudSyncEnabled"

    private static func makeContainer() -> ModelContainer {
        let syncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncKey)
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let cloudDB: ModelConfiguration.CloudKitDatabase = (syncEnabled && iCloudAvailable)
            ? .private("iCloud.com.rylandean.justellipsis")
            : .none

        // Main store: app data + feeds — optionally CloudKit-synced
        let mainSchema = Schema([QueuedLink.self, BrainEntry.self, ReadingDay.self, RSSFeed.self])

        // Articles store: ephemeral RSS articles — never synced to CloudKit
        let articlesSchema = Schema([RSSArticle.self])

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PendingLinkStore.appGroupID
        ) {
            let mainURL = groupURL.appendingPathComponent("JustEllipsis.store")
            let articlesURL = groupURL.appendingPathComponent("JustEllipsis.articles.store")

            let mainConfig = ModelConfiguration(
                "main",
                schema: mainSchema,
                url: mainURL,
                cloudKitDatabase: cloudDB
            )
            let articlesConfig = ModelConfiguration(
                "articles",
                schema: articlesSchema,
                url: articlesURL,
                cloudKitDatabase: .none
            )

            let fullSchema = Schema([
                QueuedLink.self, BrainEntry.self, ReadingDay.self,
                RSSFeed.self, RSSArticle.self
            ])
            if let container = try? ModelContainer(
                for: fullSchema,
                configurations: [mainConfig, articlesConfig]
            ) {
                return container
            }
        }

        // Fallback: single in-process store (no CloudKit)
        let fullSchema = Schema([
            QueuedLink.self, BrainEntry.self, ReadingDay.self,
            RSSFeed.self, RSSArticle.self
        ])
        let config = ModelConfiguration(
            schema: fullSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try! ModelContainer(for: fullSchema, configurations: [config])
    }
}
