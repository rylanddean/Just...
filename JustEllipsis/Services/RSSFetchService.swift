import Foundation
import SwiftData
import BackgroundTasks
import OSLog
@preconcurrency import FeedKit

private let gradingLog = Logger(subsystem: "com.rylandean.justellipsis", category: "Grading")

// MARK: - Service

struct RSSFetchService {

    static let backgroundTaskID        = "com.rylandean.justellipsis.rssfetch"
    static let gradingBackgroundTaskID = "com.rylandean.justellipsis.grading"

    // Schedule an opportunistic background grading run. No-ops if grading is disabled.
    // Safe to call repeatedly — BGTaskScheduler deduplicates pending requests.
    static func scheduleGradingBackgroundTaskIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "grading.enabled") else { return }
        let request = BGProcessingTaskRequest(identifier: gradingBackgroundTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // UserDefaults keys — read here and written by SettingsView via @AppStorage.
    static let fetchHourKey   = "rss.fetchHour"
    static let fetchMinuteKey = "rss.fetchMinute"
    static let defaultFetchHour   = 7
    static let defaultFetchMinute = 0

    static let retentionDaysKey     = "article.retentionDays"
    static let defaultRetentionDays = 2

    static func scheduleNextBackgroundTask() {
        let hour   = UserDefaults.standard.object(forKey: fetchHourKey)   as? Int ?? defaultFetchHour
        let minute = UserDefaults.standard.object(forKey: fetchMinuteKey) as? Int ?? defaultFetchMinute

        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour   = hour
        components.minute = minute

        let request = BGProcessingTaskRequest(identifier: backgroundTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        if let todayTarget = cal.date(from: components), todayTarget > Date() {
            request.earliestBeginDate = todayTarget
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
            var tomorrowComponents = cal.dateComponents([.year, .month, .day], from: tomorrow)
            tomorrowComponents.hour   = hour
            tomorrowComponents.minute = minute
            request.earliestBeginDate = cal.date(from: tomorrowComponents)
                ?? Date(timeIntervalSinceNow: 24 * 60 * 60)
        }

        try? BGTaskScheduler.shared.submit(request)
    }

    // Called from in-process refresh (e.g. when user opens Feeds tab).
    // Pruning is intentionally omitted here — it runs once daily via performDailyJob
    @MainActor
    @discardableResult
    static func fetchInProcess(container: ModelContainer, tracker: GradingProgressTracker) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.fetchAll()
            await actor.pruneOldArticles()
            await actor.summarizePendingArticles()
            await actor.gradeNewArticles(tracker: tracker)
            scheduleGradingBackgroundTaskIfNeeded()
        }
    }

    // Deduplicate RSSArticle rows by URL, keeping the richest record per URL.
    static func deduplicateInProcess(container: ModelContainer) {
        Task.detached(priority: .background) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.deduplicateArticles()
        }
    }

    // Grade any ungraded articles without doing a network fetch — used when grading is first enabled.
    @MainActor
    static func gradeInProcess(container: ModelContainer, tracker: GradingProgressTracker) {
        Task.detached(priority: .background) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.gradeNewArticles(tracker: tracker)
            scheduleGradingBackgroundTaskIfNeeded()
        }
    }

    // Fetch a single newly-added feed immediately so its articles appear right away.
    @MainActor
    static func fetchSingle(feedID: UUID, url: String, container: ModelContainer, tracker: GradingProgressTracker) {
        Task.detached(priority: .userInitiated) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.fetchOne(feedID: feedID, urlString: url)
            await actor.pruneOldArticles()
            await actor.summarizePendingArticles()
            await actor.gradeNewArticles(tracker: tracker)
            scheduleGradingBackgroundTaskIfNeeded()
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

// MARK: - Newsletter directory item (decoded from newsletters.json)

/// A pre-defined newsletter entry from the curated awesome-newsletters list.
/// `url` is the newsletter's subscribe/website page — fed directly into the
/// KtN flow as the pre-filled website URL.
struct NewsletterDirectoryItem: Codable, Identifiable, Sendable {
    var id: String { url }
    let name: String
    let url: String
    let category: String
    let description: String
}

extension NewsletterDirectoryItem {
    static func loadAll() -> [NewsletterDirectoryItem] {
        guard let fileURL = Bundle.main.url(forResource: "newsletters", withExtension: "json"),
              let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([NewsletterDirectoryItem].self, from: data)
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

// MARK: - Feed parse result (intermediate, Sendable)

private struct FeedParseResult: Sendable {
    let articles: [ParsedArticle]
    let feedType: FeedType
    let resolvedURL: String?  // non-nil if feed discovery found a real RSS/Atom URL
}

// MARK: - Fetch actor (background SwiftData context)

@ModelActor
actor RSSFetchActor {

    // Fetch a single feed by ID — used immediately after subscribing.
    func fetchOne(feedID: UUID, urlString: String) async {
        let descriptor = FetchDescriptor<RSSFeed>(predicate: #Predicate { $0.id == feedID })
        let isScraped = (try? modelContext.fetch(descriptor).first)?.feedType == .scraped
        let result = await Self.parseFeed(urlString: urlString, treatAsScraped: isScraped)
        store(result: result, feedID: feedID)
    }

    // Fetch all non-paused, non-archived feeds, parse, store new RSSArticle records.
    func fetchAll() async {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { !$0.isPaused && !$0.isArchived }
        )
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        // Parse concurrently (network-bound), collect results
        let results: [(result: FeedParseResult, feedID: UUID)] = await withTaskGroup(
            of: (FeedParseResult, UUID).self
        ) { group in
            for feed in feeds {
                let feedID = feed.id
                let urlString = feed.url
                let isScraped = feed.feedType == .scraped
                group.addTask {
                    let result = await Self.parseFeed(urlString: urlString, treatAsScraped: isScraped)
                    return (result, feedID)
                }
            }
            var collected: [(FeedParseResult, UUID)] = []
            for await pair in group { collected.append(pair) }
            return collected
        }

        // Fetch existing URLs once, then store sequentially — avoids one full table
        // scan per feed when processing a batch.
        var existingURLs = Set(
            (try? modelContext.fetch(FetchDescriptor<RSSArticle>()))?.map { $0.url } ?? []
        )
        for (result, feedID) in results {
            store(result: result, feedID: feedID, existingURLs: &existingURLs)
        }
    }

    // Prune articles published before their feed type's retention window.
    // Scraped feeds: never pruned (accumulate until unsubscribed).
    // Newsletter feeds: 30-day window (editions are infrequent; readers need time).
    // RSS feeds: user-configured window (1–7 days, default 2).
    func pruneOldArticles() async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let stored = UserDefaults.standard.object(forKey: RSSFetchService.retentionDaysKey) as? Int
        let rssDays = stored ?? RSSFetchService.defaultRetentionDays
        let rssCutoff        = Calendar.current.date(byAdding: .day, value: -rssDays, to: startOfToday) ?? startOfToday
        let newsletterCutoff = Calendar.current.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday

        let allFeeds = (try? modelContext.fetch(FetchDescriptor<RSSFeed>())) ?? []
        let scrapedIDs    = Set(allFeeds.filter { $0.feedType == .scraped    }.map { $0.id })
        let newsletterIDs = Set(allFeeds.filter { $0.feedType == .newsletter }.map { $0.id })

        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { !$0.isQueued }
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return }

        let toDelete = candidates.filter { article in
            if scrapedIDs.contains(article.feedID)    { return false }
            if newsletterIDs.contains(article.feedID) { return article.publishedAt < newsletterCutoff }
            return article.publishedAt < rssCutoff
        }

        guard !toDelete.isEmpty else { return }
        gradingLog.info("pruneOldArticles: removing \(toDelete.count) article(s)")
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // Remove duplicate RSSArticle rows that share the same URL.
    // For each duplicate group, keeps the record with the most data
    // (grade > summary > description > earliest inserted).
    func deduplicateArticles() async {
        let all = (try? modelContext.fetch(FetchDescriptor<RSSArticle>())) ?? []
        var seen: [String: RSSArticle] = [:]
        var toDelete: [RSSArticle] = []

        for article in all {
            if let existing = seen[article.url] {
                let keepNew = articleRichness(article) > articleRichness(existing)
                if keepNew {
                    toDelete.append(existing)
                    seen[article.url] = article
                } else {
                    toDelete.append(article)
                }
            } else {
                seen[article.url] = article
            }
        }

        guard !toDelete.isEmpty else { return }
        gradingLog.info("deduplicateArticles: removing \(toDelete.count) duplicate(s)")
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private func articleRichness(_ a: RSSArticle) -> Int {
        var score = 0
        if a.qualityGrade != nil    { score += 4 }
        if a.summary != nil         { score += 2 }
        if a.feedDescription != nil { score += 1 }
        return score
    }

    // Auto-archive feeds that match the user's configured unread or dead-feed thresholds.
    // Runs silently — no notification. Either condition is sufficient to archive.
    func runAutoArchive() {
        let defaults = UserDefaults.standard
        let unreadEnabled = defaults.bool(forKey: "autoArchiveUnreadEnabled")
        let deadEnabled   = defaults.bool(forKey: "autoArchiveDeadEnabled")
        guard unreadEnabled || deadEnabled else { return }

        let rawUnread = defaults.integer(forKey: "autoArchiveUnreadDays")
        let rawDead   = defaults.integer(forKey: "autoArchiveDeadDays")
        let unreadDays = rawUnread > 0 ? rawUnread : 7
        let deadDays   = rawDead   > 0 ? rawDead   : 14

        let now = Date()
        let unreadCutoff = Calendar.current.date(byAdding: .day, value: -unreadDays, to: now) ?? now
        let deadCutoff   = Calendar.current.date(byAdding: .day, value: -deadDays,   to: now) ?? now

        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { !$0.isArchived && !$0.isPaused }
        )
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        // The unread check measures whether the user ignored a feed while actively using
        // the app. If the user hasn't opened the app since before the cutoff, the gap is
        // absence — not disinterest — so skip the unread check entirely.
        let lastOpenAt = UserDefaults.standard.object(forKey: "lastAppOpenAt") as? Date
        let userWasActiveForUnread = lastOpenAt.map { $0 >= unreadCutoff } ?? false

        var changed = false
        for feed in feeds {
            if unreadEnabled && userWasActiveForUnread {
                let neverRead = feed.lastReadAt == nil
                let staleRead = feed.lastReadAt.map { $0 < unreadCutoff } ?? false
                let oldEnough = feed.lastFetchedAt.map { $0 < unreadCutoff } ?? false
                if staleRead || (neverRead && oldEnough) {
                    feed.isArchived = true
                    feed.archiveReason = "unread:\(unreadDays)"
                    changed = true
                    continue
                }
            }
            if deadEnabled {
                // Dead-feed check is about feed behaviour, not user presence —
                // a feed that stopped publishing is dead regardless of app opens.
                let noArticles    = feed.lastArticleAt == nil
                let staleFeed     = feed.lastArticleAt.map { $0 < deadCutoff } ?? false
                let polledLongAgo = feed.lastFetchedAt.map { $0 < deadCutoff } ?? false
                if staleFeed || (noArticles && polledLongAgo) {
                    feed.isArchived = true
                    feed.archiveReason = "dead:\(deadDays)"
                    changed = true
                }
            }
        }
        if changed { try? modelContext.save() }
    }

    // Full daily job: fetch all feeds, prune stale articles, grade, make picks, promote to queue.
    func performDailyJob() async {
        await fetchAll()
        await pruneOldArticles()
        await summarizePendingArticles()
        await gradeNewArticles(tracker: nil)

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
        runAutoArchive()
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
            if let original = try? modelContext.model(for: snap.persistentModelID) as? RSSArticle {
                original.isQueued = true
            }
            inserted += 1
        }
        if inserted > 0 { try? modelContext.save() }
    }

    // Mark a feed's lastFetchedAt timestamp. Optionally advances lastArticleAt to the
    // most recent article date seen in this fetch batch — only moves forward, never back.
    func markFetched(feedID: UUID, latestArticleAt: Date? = nil) {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { $0.id == feedID }
        )
        guard let feed = try? modelContext.fetch(descriptor).first else { return }
        feed.lastFetchedAt = Date()
        if let date = latestArticleAt {
            feed.lastArticleAt = max(feed.lastArticleAt ?? .distantPast, date)
        }
        try? modelContext.save()
    }

    // MARK: - Private

    // Stores articles and updates feedType / resolvedURL on the parent RSSFeed if they changed.
    // Used by fetchOne — builds its own existingURLs set for a single-feed store.
    private func store(result: FeedParseResult, feedID: UUID) {
        var existingURLs = Set(
            (try? modelContext.fetch(FetchDescriptor<RSSArticle>()))?.map { $0.url } ?? []
        )
        store(result: result, feedID: feedID, existingURLs: &existingURLs)
    }

    // Batch variant used by fetchAll — caller pre-fetches existingURLs once and passes it
    // in so each feed doesn't trigger a redundant full table scan.
    private func store(result: FeedParseResult, feedID: UUID, existingURLs: inout Set<String>) {
        var isNewsletter = false
        var autoQueue = false
        let descriptor = FetchDescriptor<RSSFeed>(predicate: #Predicate { $0.id == feedID })
        if let feed = try? modelContext.fetch(descriptor).first {
            isNewsletter = feed.feedType == .newsletter
            autoQueue = feed.isFavourite
            var changed = false
            // Newsletter feeds always fetch as a standard Atom feed via FeedKit.
            // The parse result carries .rss, but we must not overwrite the stored .newsletter type.
            if feed.feedType != .newsletter {
                let newRaw = result.feedType.rawValue
                if feed.feedTypeRaw != newRaw {
                    feed.feedTypeRaw = newRaw
                    changed = true
                }
            }
            if let resolved = result.resolvedURL, feed.url != resolved {
                feed.url = resolved
                changed = true
            }
            if changed { try? modelContext.save() }
        }
        store(articles: result.articles, feedID: feedID, existingURLs: &existingURLs, backfillDescriptions: isNewsletter, autoQueue: autoQueue)
    }

    private func store(articles: [ParsedArticle], feedID: UUID, existingURLs: inout Set<String>, backfillDescriptions: Bool = false, autoQueue: Bool = false) {
        // Also deduplicate within the incoming batch itself.
        var seenInBatch = Set<String>()

        var inserted = 0
        var autoQueuePending: [(url: String, title: String)] = []
        var descriptionBackfills: [(url: String, desc: String)] = []
        var latestNewArticleDate: Date? = nil
        for article in articles {
            guard seenInBatch.insert(article.url).inserted else { continue }

            if existingURLs.contains(article.url) {
                // For newsletter feeds, backfill feedDescription if it's missing or was
                // polluted with raw CSS (style blocks that stripHTML previously left intact).
                if backfillDescriptions, let newDesc = article.feedDescription {
                    descriptionBackfills.append((article.url, newDesc))
                }
                continue
            }
            let record = RSSArticle(
                feedID: feedID,
                url: article.url,
                title: article.title,
                publishedAt: article.publishedAt,
                feedDescription: article.feedDescription
            )
            record.isQueued = autoQueue
            modelContext.insert(record)
            existingURLs.insert(article.url)  // keep set in sync for subsequent feeds
            inserted += 1
            if autoQueue {
                autoQueuePending.append((article.url, article.title))
            }
            latestNewArticleDate = max(latestNewArticleDate ?? .distantPast, article.publishedAt)
        }

        // Apply description backfills — only when the stored value is absent or CSS-polluted.
        for backfill in descriptionBackfills {
            let url = backfill.url
            if let existing = try? modelContext.fetch(FetchDescriptor<RSSArticle>(predicate: #Predicate { $0.url == url })).first {
                let current = existing.feedDescription ?? ""
                if current.isEmpty || current.contains("{") {
                    existing.feedDescription = backfill.desc
                }
            }
        }

        // Promote auto-queued articles into QueuedLink so they appear in the reading queue.
        if !autoQueuePending.isEmpty {
            let existingQueue = (try? modelContext.fetch(FetchDescriptor<QueuedLink>())) ?? []
            let existingQueueURLs = Set(existingQueue.map { $0.url })
            var order = (existingQueue.map { $0.sortOrder }.max() ?? -1) + 1
            for item in autoQueuePending {
                guard !existingQueueURLs.contains(item.url) else { continue }
                let link = QueuedLink(
                    url: item.url,
                    sortOrder: order,
                    title: item.title,
                    source: .rss(feedID: feedID)
                )
                modelContext.insert(link)
                order += 1
            }
        }

        if inserted > 0 || !descriptionBackfills.isEmpty {
            markFetched(feedID: feedID, latestArticleAt: latestNewArticleDate)
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

    // Grades ungraded articles using on-device AI. No-ops when grading is disabled or AI is unavailable.
    // Pass nil tracker from background tasks where there is no UI to update.
    func gradeNewArticles(tracker: GradingProgressTracker?) async {
        guard #available(iOS 26, *) else {
            gradingLog.debug("gradeNewArticles: skipped — iOS 26 unavailable")
            return
        }
        guard UserDefaults.standard.bool(forKey: "grading.enabled") else {
            gradingLog.debug("gradeNewArticles: skipped — grading.enabled is false")
            return
        }
        guard IntelligenceService.isAvailable else {
            gradingLog.warning("gradeNewArticles: skipped — Apple Intelligence unavailable")
            if let tracker { await MainActor.run { tracker.markFailed() } }
            return
        }

        struct Stub: Sendable {
            let id: PersistentIdentifier
            let articleID: UUID
            let title: String
            let desc: String
            let source: String?
        }
        let descriptor = FetchDescriptor<RSSArticle>(
            sortBy: [SortDescriptor(\RSSArticle.publishedAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let stubs: [Stub] = all.compactMap { article in
            guard article.qualityGrade == nil else { return nil }
            let desc = article.summary ?? article.feedDescription ?? ""
            let source = URL(string: article.url).flatMap { url in
                url.host.map { host in
                    host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                }
            }
            return Stub(id: article.persistentModelID, articleID: article.id,
                        title: article.title, desc: desc, source: source)
        }

        guard !stubs.isEmpty else {
            if let tracker { await MainActor.run { tracker.markFinished() } }
            return
        }

        gradingLog.info("gradeNewArticles: \(stubs.count) ungraded (newest first)")

        var graded = 0
        var failed = 0
        for stub in stubs {
            guard !Task.isCancelled else {
                let remaining = stubs.count - graded - failed
                gradingLog.info("gradeNewArticles: cancelled — \(graded) graded, \(remaining) remaining")
                if let tracker { await MainActor.run { tracker.markCancelled(graded: graded, remaining: remaining) } }
                return
            }
            if let tracker { await MainActor.run { tracker.markActive(stub.articleID) } }
            let grade = await IntelligenceService.gradeQuality(title: stub.title, description: stub.desc, source: stub.source)
            gradingLog.debug("gradeNewArticles: '\(stub.title.prefix(60))' → \(grade.map { "\($0)" } ?? "nil (→ worthIt fallback)")")
            if let article = try? modelContext.model(for: stub.id) as? RSSArticle {
                article.qualityGrade = grade ?? .worthIt
                try? modelContext.save()
                graded += 1
            } else {
                gradingLog.warning("gradeNewArticles: failed to resolve model for '\(stub.title.prefix(60))'")
                failed += 1
            }
            if let tracker { await MainActor.run { tracker.markDone(stub.articleID) } }
        }
        gradingLog.info("gradeNewArticles: done — \(graded) graded, \(failed) failed")
        if let tracker { await MainActor.run { tracker.markFinished() } }
    }

    // MARK: - Parsing

    // Orchestrates FeedKit → WebFeedScraper fallback.
    // treatAsScraped skips FeedKit for feeds already known to require scraping.
    private static func parseFeed(urlString: String, treatAsScraped: Bool = false) async -> FeedParseResult {
        if !treatAsScraped {
            let articles = await parseFeedKit(urlString: urlString)
            if !articles.isEmpty {
                return FeedParseResult(articles: articles, feedType: .rss, resolvedURL: nil)
            }
        }

        guard let scraped = await WebFeedScraper.scrape(urlString: urlString) else {
            return FeedParseResult(articles: [], feedType: treatAsScraped ? .scraped : .rss, resolvedURL: nil)
        }

        // Scraper found a real alternate feed — try FeedKit on that URL.
        if let discoveredURL = scraped.discoveredFeedURL {
            let articles = await parseFeedKit(urlString: discoveredURL)
            if !articles.isEmpty {
                return FeedParseResult(articles: articles, feedType: .rss, resolvedURL: discoveredURL)
            }
        }

        return FeedParseResult(
            articles: scraped.articles,
            feedType: scraped.articles.isEmpty ? (treatAsScraped ? .scraped : .rss) : .scraped,
            resolvedURL: nil
        )
    }

    private static let feedKitSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func parseFeedKit(urlString: String) async -> [ParsedArticle] {
        guard let url = URL(string: urlString) else { return [] }

        guard let (data, _) = try? await feedKitSession.data(from: url) else { return [] }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                let parser = FeedParser(data: data)
                let result = parser.parse()
                switch result {
                case .success(let feed): continuation.resume(returning: Self.extract(feed: feed))
                case .failure:          continuation.resume(returning: [])
                }
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
            .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<script[^>]*>[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;",  with: "<")
            .replacingOccurrences(of: "&gt;",  with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\\s+",  with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(2000))
    }
}
