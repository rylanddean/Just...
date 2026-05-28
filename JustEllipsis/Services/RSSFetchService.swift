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

    // Fetch all non-paused feeds, parse, store new RSSArticle records.
    func fetchAll() async {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { !$0.isPaused }
        )
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                let feedID = feed.id
                let urlString = feed.url
                let isScraped = feed.feedType == .scraped
                group.addTask {
                    let result = await Self.parseFeed(urlString: urlString, treatAsScraped: isScraped)
                    await self.store(result: result, feedID: feedID)
                }
            }
        }
    }

    // Prune articles published before their feed type's retention window.
    // Scraped feeds: never pruned (accumulate until unsubscribed).
    // Newsletter feeds: 30-day window (editions are infrequent; readers need time).
    // RSS feeds: 1-day window (standard behaviour).
    func pruneOldArticles() async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let rssCutoff        = Calendar.current.date(byAdding: .day, value: -1,  to: startOfToday) ?? startOfToday
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

    // Stores articles and updates feedType / resolvedURL on the parent RSSFeed if they changed.
    private func store(result: FeedParseResult, feedID: UUID) {
        let descriptor = FetchDescriptor<RSSFeed>(predicate: #Predicate { $0.id == feedID })
        if let feed = try? modelContext.fetch(descriptor).first {
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
        store(articles: result.articles, feedID: feedID)
    }

    private func store(articles: [ParsedArticle], feedID: UUID) {
        // Check existing URLs globally — not just for this feed — so the same URL
        // syndicated by two subscribed feeds never creates duplicate RSSArticle rows.
        let existingURLs = Set(
            (try? modelContext.fetch(FetchDescriptor<RSSArticle>()))?.map { $0.url } ?? []
        )

        // Also deduplicate within the incoming batch itself.
        var seenInBatch = Set<String>()

        var inserted = 0
        for article in articles {
            guard !existingURLs.contains(article.url),
                  seenInBatch.insert(article.url).inserted else { continue }
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

    private static func parseFeedKit(urlString: String) async -> [ParsedArticle] {
        guard let url = URL(string: urlString) else { return [] }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        guard let (data, _) = try? await session.data(from: url) else { return [] }

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
