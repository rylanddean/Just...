import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct JustEllipsisApp: App {

    let container: ModelContainer = makeContainer()
    @State private var router = AppRouter()
    @State private var gradingTracker = GradingProgressTracker()
    @State private var pipelineTracker = PipelineProgressTracker()
    @State private var healthKit = HealthKitService()
    @Environment(\.scenePhase) private var scenePhase

    static let lastAppOpenKey = "lastAppOpenAt"

    init() {
        registerRSSBackgroundTask()
        registerGradingBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environment(router)
                .environment(gradingTracker)
                .environment(pipelineTracker)
                .environment(healthKit)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UserDefaults.standard.set(Date(), forKey: Self.lastAppOpenKey)
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
                await actor.performDailyJob(pipelineTracker: pipelineTracker)
                RSSFetchService.scheduleNextBackgroundTask()
                processingTask.setTaskCompleted(success: true)
            }
            processingTask.expirationHandler = { taskHandle.cancel() }
        }
    }

    private func registerGradingBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: RSSFetchService.gradingBackgroundTaskID,
            using: nil
        ) { [self] bgTask in
            guard let processingTask = bgTask as? BGProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            let taskHandle = Task {
                let actor = RSSFetchActor(modelContainer: container)
                await actor.gradeNewArticles(tracker: nil)
                // Re-queue so the next backgrounding continues where this left off.
                RSSFetchService.scheduleGradingBackgroundTaskIfNeeded()
                processingTask.setTaskCompleted(success: true)
            }
            processingTask.expirationHandler = {
                taskHandle.cancel()
                // Still re-schedule — expiration means time ran out, not that we're done.
                RSSFetchService.scheduleGradingBackgroundTaskIfNeeded()
            }
        }
    }

    // MARK: - URL handling

    // Handles feed URLs launched from Safari/other apps.
    // Supported examples:
    // - feed://example.com/feed.xml
    // - feeds://example.com/feed.xml
    // - feed:https://example.com/feed.xml
    // - justellipsis://add-feed?url=https://example.com/feed.xml
    private func handleOpenURL(_ url: URL) {
        guard let feedURLString = extractFeedURLString(from: url) else { return }
        router.pendingFeedURL = feedURLString
        router.selectedTab = 1 // Feeds tab
    }

    private func extractFeedURLString(from incomingURL: URL) -> String? {
        let scheme = incomingURL.scheme?.lowercased()
        let resolved: String?

        switch scheme {
        case "feed", "feeds":
            if let host = incomingURL.host, !host.isEmpty {
                // feed://example.com/feed.xml -> https://example.com/feed.xml
                var components = URLComponents()
                components.scheme = "https"
                components.host = host
                components.path = incomingURL.path
                components.query = incomingURL.query
                components.fragment = incomingURL.fragment
                resolved = components.string
            } else {
                // feed:https://example.com/feed.xml -> https://example.com/feed.xml
                let raw = incomingURL.absoluteString
                resolved = raw.hasPrefix("feed:") ? String(raw.dropFirst("feed:".count)) : nil
            }

        case "justellipsis", "just":
            let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []
            let deepLinkURL = queryItems.first { item in
                let name = item.name.lowercased()
                return name == "url" || name == "feed" || name == "feedurl"
            }?.value
            resolved = deepLinkURL

        case "file":
            // Opened via "Open in Just…" banner in Safari — iOS downloads the RSS/Atom XML
            // to a temp file and passes the file URL here. Scan the raw XML for the
            // atom:link rel="self" element, which carries the canonical feed URL.
            guard let data = try? Data(contentsOf: incomingURL),
                  let xml = String(data: data, encoding: .utf8) else { return nil }
            resolved = Self.extractAtomSelfLink(from: xml)

        case "http", "https":
            // For future universal-link support, allow direct web URLs too.
            resolved = incomingURL.absoluteString

        default:
            resolved = nil
        }

        guard let resolved,
              let resolvedURL = URL(string: resolved),
              let resolvedScheme = resolvedURL.scheme?.lowercased(),
              resolvedScheme == "http" || resolvedScheme == "https"
        else {
            return nil
        }

        return resolved
    }

    // Extracts the href from the first <atom:link rel="self"> (or <link rel="self">)
    // element in raw RSS/Atom XML. Handles both attribute orderings.
    private static func extractAtomSelfLink(from xml: String) -> String? {
        let patterns = [
            #"<(?:atom:)?link\b[^>]*\brel="self"[^>]*\bhref="([^"]+)""#,
            #"<(?:atom:)?link\b[^>]*\bhref="([^"]+)"[^>]*\brel="self""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsRange = NSRange(xml.startIndex..., in: xml)
            if let match = regex.firstMatch(in: xml, range: nsRange),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
        }
        return nil
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

            // Wipe the main store when a force-restore was scheduled in Settings.
            // CloudKit re-downloads all records into the fresh store on first open.
            CloudSyncService.applyPendingRestoreIfNeeded(storeURL: mainURL)

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
