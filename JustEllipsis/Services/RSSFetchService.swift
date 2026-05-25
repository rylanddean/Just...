import Foundation
import SwiftData
import BackgroundTasks
@preconcurrency import FeedKit

// MARK: - Service

struct RSSFetchService {

    static let backgroundTaskID = "com.rylandean.justellipsis.rssfetch"

    static func scheduleNextBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Aim for a 7AM fetch so picks are ready when the user wakes
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        if let today7AM = Calendar.current.date(from: components),
           today7AM > Date() {
            request.earliestBeginDate = today7AM
        } else {
            // Already past 7AM — schedule for tomorrow
            request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60 * 60)
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    // Called from in-process refresh (e.g. when user opens Feeds tab)
    @MainActor
    static func fetchInProcess(container: ModelContainer) {
        Task.detached(priority: .background) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.fetchAll()
            await actor.pruneOldArticles()
            await actor.summarizePendingArticles()
        }
    }
}

// MARK: - Feed directory item (decoded from feeds.json)

struct FeedDirectoryItem: Codable, Identifiable, Sendable {
    var id: String { url }
    let name: String
    let url: String
    let category: String
    let description: String
}

extension FeedDirectoryItem {
    static func loadAll() -> [FeedDirectoryItem] {
        guard let url = Bundle.main.url(forResource: "feeds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([FeedDirectoryItem].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - Parsed article (intermediate, Sendable for actor crossing)

struct ParsedArticle: Sendable {
    let url: String
    let title: String
    let publishedAt: Date
    let feedDescription: String?
}

// MARK: - Fetch actor (background SwiftData context)

@ModelActor
actor RSSFetchActor {

    // Fetch all non-paused feeds, parse with FeedKit, store new RSSArticle records.
    func fetchAll() async {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { !$0.isPaused }
        )
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                let feedID = feed.id
                let urlString = feed.url
                group.addTask {
                    let articles = await Self.parseFeed(urlString: urlString)
                    await self.store(articles: articles, feedID: feedID)
                }
            }
        }
    }

    // Prune articles older than 7 days that haven't been promoted to the queue.
    func pruneOldArticles() async {
        let cutoff = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.publishedAt < cutoff && !$0.isQueued }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // Full daily job: fetch all feeds, prune stale articles, make picks, promote to queue.
    func performDailyJob() async {
        await fetchAll()
        await pruneOldArticles()
        await summarizePendingArticles()

        // Extract Sendable snapshots before crossing the isolation boundary.
        let articleSnapshots: [ArticleSnapshot] = ((try? modelContext.fetch(FetchDescriptor<RSSArticle>())) ?? [])
            .filter { !$0.isQueued }
            .map { ArticleSnapshot(persistentModelID: $0.persistentModelID, url: $0.url, title: $0.title, feedID: $0.feedID, publishedAt: $0.publishedAt) }

        let brainSnapshots: [BrainSnapshot] = ((try? modelContext.fetch(FetchDescriptor<BrainEntry>())) ?? [])
            .map { BrainSnapshot(title: $0.title, reflection: $0.reflection) }

        let queueURLs = Set(((try? modelContext.fetch(FetchDescriptor<QueuedLink>())) ?? []).map { $0.url })

        let picks = await RSSRecommendationEngine.makePicks(
            freshArticles: articleSnapshots,
            brainEntries: brainSnapshots,
            existingQueueURLs: queueURLs
        )

        promotePicksToQueue(picks: picks)
    }

    // Insert AI picks into the queue; re-fetches originals by persistentModelID to mark isQueued.
    func promotePicksToQueue(picks: [ArticleSnapshot]) {
        let existing = (try? modelContext.fetch(FetchDescriptor<QueuedLink>())) ?? []
        let existingURLs = Set(existing.map { $0.url })
        let maxOrder = existing.map { $0.sortOrder }.max() ?? -1

        var inserted = 0
        for snap in picks {
            guard !existingURLs.contains(snap.url) else { continue }
            let link = QueuedLink(
                url: snap.url,
                sortOrder: maxOrder + 1 + inserted,
                title: snap.title,
                source: .aiPick
            )
            modelContext.insert(link)
            // Mark the original RSSArticle as queued so it isn't re-picked.
            if let original = try? modelContext.model(for: snap.persistentModelID) as? RSSArticle {
                original.isQueued = true
            }
            inserted += 1
        }
        if inserted > 0 { try? modelContext.save() }
    }

    // Mark a feed's lastFetchedAt timestamp (called after a successful fetch).
    func markFetched(feedID: UUID) {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { $0.id == feedID }
        )
        guard let feed = try? modelContext.fetch(descriptor).first else { return }
        feed.lastFetchedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Private

    private func store(articles: [ParsedArticle], feedID: UUID) {
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.feedID == feedID }
        )
        let existing = Set((try? modelContext.fetch(descriptor))?.map { $0.url } ?? [])

        var inserted = 0
        for article in articles where !existing.contains(article.url) {
            let record = RSSArticle(
                feedID: feedID,
                url: article.url,
                title: article.title,
                publishedAt: article.publishedAt,
                feedDescription: article.feedDescription
            )
            modelContext.insert(record)
            inserted += 1
        }
        if inserted > 0 {
            markFetched(feedID: feedID)
            try? modelContext.save()
        }
    }

    // Generates AI two-sentence summaries for articles that have a description but no summary yet.
    // No-ops on iOS < 26 or when Apple Intelligence is unavailable.
    func summarizePendingArticles() async {
        guard #available(iOS 26, *) else { return }
        guard IntelligenceService.isAvailable else { return }

        struct Stub: Sendable { let id: PersistentIdentifier; let title: String; let desc: String }
        let all = (try? modelContext.fetch(FetchDescriptor<RSSArticle>())) ?? []
        let stubs: [Stub] = all.compactMap { article in
            guard let desc = article.feedDescription, article.summary == nil else { return nil }
            return Stub(id: article.persistentModelID, title: article.title, desc: desc)
        }

        for stub in stubs {
            guard let generated = try? await IntelligenceService.summarizeFeedItem(title: stub.title, description: stub.desc) else { continue }
            if let article = try? modelContext.model(for: stub.id) as? RSSArticle {
                article.summary = generated
            }
        }
        if !stubs.isEmpty { try? modelContext.save() }
    }

    // Pure parsing — runs on the cooperative pool, returns a Sendable value.
    private static func parseFeed(urlString: String) async -> [ParsedArticle] {
        guard let url = URL(string: urlString) else { return [] }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        guard let (data, _) = try? await session.data(from: url) else { return [] }

        return await withCheckedContinuation { continuation in
            // FeedKit parsing is synchronous — push off main thread.
            Task.detached(priority: .background) {
                let parser = FeedParser(data: data)
                let result = parser.parse()
                let articles: [ParsedArticle]
                switch result {
                case .success(let feed):
                    articles = Self.extract(feed: feed)
                case .failure:
                    articles = []
                }
                continuation.resume(returning: articles)
            }
        }
    }

    private static func extract(feed: Feed) -> [ParsedArticle] {
        switch feed {
        case .rss(let rss):
            return (rss.items ?? []).compactMap { item -> ParsedArticle? in
                guard let link = item.link, !link.isEmpty else { return nil }
                let desc = (item.description ?? item.content?.contentEncoded)
                    .map { stripHTML($0) }
                return ParsedArticle(
                    url: link,
                    title: item.title ?? link,
                    publishedAt: item.pubDate ?? Date(),
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        case .atom(let atom):
            return (atom.entries ?? []).compactMap { entry -> ParsedArticle? in
                let link = entry.links?.first?.attributes?.href ?? ""
                guard !link.isEmpty else { return nil }
                let desc = (entry.summary?.value ?? entry.content?.value)
                    .map { stripHTML($0) }
                return ParsedArticle(
                    url: link,
                    title: entry.title ?? link,
                    publishedAt: entry.published ?? entry.updated ?? Date(),
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        case .json(let json):
            return (json.items ?? []).compactMap { item -> ParsedArticle? in
                guard let link = item.url, !link.isEmpty else { return nil }
                let desc = (item.summary ?? item.contentText)
                    .map { stripHTML($0) }
                return ParsedArticle(
                    url: link,
                    title: item.title ?? link,
                    publishedAt: item.datePublished ?? Date(),
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        }
    }

    private static func stripHTML(_ html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(500))
    }
}
