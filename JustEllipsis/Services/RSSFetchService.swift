import Foundation
import SwiftData
import BackgroundTasks
@preconcurrency import FeedKit

// MARK: - Service

struct RSSFetchService {

    static let backgroundTaskID = "com.rylandean.justellipsis.rssfetch"

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

    @MainActor
    static func fetchInProcess(container: ModelContainer) {
        Task.detached(priority: .background) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.fetchAll()
            await actor.summarizePendingArticles()
        }
    }

    @MainActor
    static func fetchSingle(feedID: UUID, url: String, feedType: FeedType = .article, container: ModelContainer) {
        Task.detached(priority: .userInitiated) {
            let actor = RSSFetchActor(modelContainer: container)
            await actor.fetchOne(feedID: feedID, urlString: url, feedType: feedType)
        }
    }
}

// MARK: - Feed type detection (pure, no network)

extension RSSFetchService {
    static func detectFeedType(from prefix: String) -> FeedType {
        let lower = prefix.lowercased()
        if lower.contains("xmlns:itunes") ||
           lower.contains("xmlns:podcast") ||
           lower.contains("<enclosure type=\"audio/") ||
           lower.contains("<itunes:type>") {
            return .podcast
        }
        return .article
    }
}

// MARK: - Feed directory item (decoded from feeds.json)

struct FeedDirectoryItem: Codable, Identifiable, Sendable {
    var id: String { url }
    let name: String
    let url: String
    let category: String
    let description: String
    let feedType: FeedType?
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

// MARK: - Parsed article / episode (intermediate, Sendable for actor crossing)

struct ParsedArticle: Sendable {
    let url: String
    let title: String
    let publishedAt: Date
    let feedDescription: String?
    let isEpisode: Bool
    let transcriptURL: String?
    let transcriptFormatRaw: String?
}

// MARK: - Fetch actor (background SwiftData context)

@ModelActor
actor RSSFetchActor {

    func fetchOne(feedID: UUID, urlString: String, feedType: FeedType = .article) async {
        let articles = await Self.parseFeed(urlString: urlString, feedType: feedType)
        let feedTitle = feedTitle(for: feedID)
        await storeAndQueue(articles: articles, feedID: feedID, feedType: feedType, feedTitle: feedTitle)
    }

    func fetchAll() async {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { !$0.isPaused }
        )
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                let feedID = feed.id
                let urlString = feed.url
                let feedType = feed.feedType
                let feedTitle = feed.title
                group.addTask {
                    let articles = await Self.parseFeed(urlString: urlString, feedType: feedType)
                    await self.storeAndQueue(
                        articles: articles,
                        feedID: feedID,
                        feedType: feedType,
                        feedTitle: feedTitle
                    )
                }
            }
        }
    }

    func pruneOldArticles() async {
        let cutoff = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.publishedAt < cutoff && !$0.isQueued }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        stale.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    func performDailyJob() async {
        await fetchAll()
        await pruneOldArticles()
        await summarizePendingArticles()
        await recheckMissingTranscripts()

        // Extract Sendable snapshots before crossing the isolation boundary.
        // Exclude podcast episodes — they are auto-queued during storeAndQueue.
        let articleSnapshots: [ArticleSnapshot] = ((try? modelContext.fetch(FetchDescriptor<RSSArticle>())) ?? [])
            .filter { !$0.isQueued && !$0.isEpisode }
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

    func markFetched(feedID: UUID) {
        let descriptor = FetchDescriptor<RSSFeed>(
            predicate: #Predicate { $0.id == feedID }
        )
        guard let feed = try? modelContext.fetch(descriptor).first else { return }
        feed.lastFetchedAt = Date()
        try? modelContext.save()
    }

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

    // Re-check QueuedLinks that are podcast episodes with no transcript, added within the last 48 hours.
    func recheckMissingTranscripts() async {
        let cutoff = Date(timeIntervalSinceNow: -48 * 60 * 60)
        let descriptor = FetchDescriptor<QueuedLink>(
            predicate: #Predicate { $0.isEpisode && $0.transcriptStateRaw == "unavailable" && $0.addedAt > cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }

        for link in stale {
            guard let transcriptURLString = link.transcriptURL,
                  let transcriptURL = URL(string: transcriptURLString),
                  let formatRaw = link.transcriptFormatRaw,
                  let format = TranscriptFormat.from(formatRaw) else { continue }

            let episodeTitle = link.title ?? ""
            let showName = link.showName ?? ""
            let linkID = link.persistentModelID
            let container = modelContainer

            link.transcriptState = .generating
            try? modelContext.save()

            Task.detached(priority: .background) {
                await Self.generateAndStore(
                    transcriptURL: transcriptURL,
                    format: format,
                    episodeTitle: episodeTitle,
                    showName: showName,
                    linkID: linkID,
                    container: container
                )
            }
        }
    }

    // MARK: - Private

    private func feedTitle(for feedID: UUID) -> String {
        let descriptor = FetchDescriptor<RSSFeed>(predicate: #Predicate { $0.id == feedID })
        return (try? modelContext.fetch(descriptor).first?.title) ?? ""
    }

    // Store articles; auto-queue podcast episodes (newest N with transcript URLs).
    private func storeAndQueue(
        articles: [ParsedArticle],
        feedID: UUID,
        feedType: FeedType,
        feedTitle: String
    ) async {
        let existingURLs = Set(
            (try? modelContext.fetch(FetchDescriptor<RSSArticle>()))?.map { $0.url } ?? []
        )
        let existingQueueURLs = Set(
            (try? modelContext.fetch(FetchDescriptor<QueuedLink>()))?.map { $0.url } ?? []
        )

        var seenInBatch = Set<String>()
        var newEpisodes: [RSSArticle] = []
        var inserted = 0

        for article in articles {
            guard !existingURLs.contains(article.url),
                  seenInBatch.insert(article.url).inserted else { continue }

            let record = RSSArticle(
                feedID: feedID,
                url: article.url,
                title: article.title,
                publishedAt: article.publishedAt,
                feedDescription: article.feedDescription,
                isEpisode: article.isEpisode,
                transcriptURL: article.transcriptURL,
                transcriptFormatRaw: article.transcriptFormatRaw
            )
            modelContext.insert(record)
            inserted += 1

            if article.isEpisode { newEpisodes.append(record) }
        }

        if inserted > 0 {
            markFetched(feedID: feedID)
            try? modelContext.save()
        }

        // Auto-queue the 3 most recent new podcast episodes.
        guard feedType == .podcast, !newEpisodes.isEmpty else { return }

        let toQueue = newEpisodes
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(3)
            .filter { !existingQueueURLs.contains($0.url) }

        let existing = (try? modelContext.fetch(FetchDescriptor<QueuedLink>())) ?? []
        var maxOrder = existing.map { $0.sortOrder }.max() ?? -1

        for episode in toQueue {
            let hasTranscript = episode.transcriptURL != nil
            let state: TranscriptState = hasTranscript ? .generating : .unavailable

            let link = QueuedLink(
                url: episode.url,
                sortOrder: maxOrder + 1,
                title: episode.title,
                source: .rss(feedID: feedID),
                isEpisode: true,
                transcriptState: state,
                transcriptURL: episode.transcriptURL,
                transcriptFormatRaw: episode.transcriptFormatRaw,
                showName: feedTitle
            )
            modelContext.insert(link)
            episode.isQueued = true
            maxOrder += 1
        }
        try? modelContext.save()

        // Fire transcript generation for each queued episode that has a URL.
        for episode in toQueue where episode.transcriptURL != nil {
            guard let transcriptURLString = episode.transcriptURL,
                  let transcriptURL = URL(string: transcriptURLString),
                  let formatRaw = episode.transcriptFormatRaw,
                  let format = TranscriptFormat.from(formatRaw) else { continue }

            // Find the QueuedLink we just inserted.
            let episodeURL = episode.url
            let descriptor = FetchDescriptor<QueuedLink>(
                predicate: #Predicate { $0.url == episodeURL }
            )
            guard let link = try? modelContext.fetch(descriptor).first else { continue }

            let episodeTitle = episode.title
            let linkID = link.persistentModelID
            let container = modelContainer

            Task.detached(priority: .background) {
                await Self.generateAndStore(
                    transcriptURL: transcriptURL,
                    format: format,
                    episodeTitle: episodeTitle,
                    showName: feedTitle,
                    linkID: linkID,
                    container: container
                )
            }
        }
    }

    // Fetch transcript, strip it, generate article, save to QueuedLink.
    private static func generateAndStore(
        transcriptURL: URL,
        format: TranscriptFormat,
        episodeTitle: String,
        showName: String,
        linkID: PersistentIdentifier,
        container: ModelContainer
    ) async {
        guard let raw = await PodcastTranscriptService.fetch(url: transcriptURL, format: format) else {
            await markTranscriptState(linkID: linkID, state: .unavailable, container: container)
            return
        }
        let stripped = PodcastTranscriptService.strip(rawTranscript: raw, format: format)
        guard !stripped.isEmpty else {
            await markTranscriptState(linkID: linkID, state: .unavailable, container: container)
            return
        }

        guard #available(iOS 26, *), IntelligenceService.isAvailable else {
            await markTranscriptState(linkID: linkID, state: .unavailable, container: container)
            return
        }

        guard let generated = try? await IntelligenceService.generateArticle(
            from: stripped,
            episodeTitle: episodeTitle,
            showName: showName
        ) else {
            await markTranscriptState(linkID: linkID, state: .unavailable, container: container)
            return
        }

        let context = ModelContext(container)
        guard let link = try? context.model(for: linkID) as? QueuedLink else { return }
        link.generatedContent = generated
        link.transcriptState = .ready
        link.prefetchState = .ready
        try? context.save()
    }

    private static func markTranscriptState(
        linkID: PersistentIdentifier,
        state: TranscriptState,
        container: ModelContainer
    ) async {
        let context = ModelContext(container)
        guard let link = try? context.model(for: linkID) as? QueuedLink else { return }
        link.transcriptState = state
        try? context.save()
    }

    // MARK: - Pure parsing

    private static func parseFeed(urlString: String, feedType: FeedType = .article) async -> [ParsedArticle] {
        guard let url = URL(string: urlString) else { return [] }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        guard let (data, _) = try? await session.data(from: url) else { return [] }

        // Build a transcript-URL index from the raw XML (podcast:transcript tags).
        let rawXML = String(data: data, encoding: .utf8) ?? ""
        let transcriptIndex: [String: (url: String, formatRaw: String)]
        if feedType == .podcast {
            transcriptIndex = extractTranscriptIndex(from: rawXML)
        } else {
            transcriptIndex = [:]
        }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                let parser = FeedParser(data: data)
                let result = parser.parse()
                let articles: [ParsedArticle]
                switch result {
                case .success(let feed):
                    articles = Self.extract(feed: feed, feedType: feedType, transcriptIndex: transcriptIndex)
                case .failure:
                    articles = []
                }
                continuation.resume(returning: articles)
            }
        }
    }

    // Parse <podcast:transcript> tags from raw XML, returning a map from episode link → (url, format).
    private static func extractTranscriptIndex(from xml: String) -> [String: (url: String, formatRaw: String)] {
        var result: [String: (url: String, formatRaw: String)] = [:]
        let itemPattern = #"<item\b[^>]*>([\s\S]*?)</item>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) else {
            return result
        }
        let nsXML = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsXML.length))

        for match in matches {
            let block = nsXML.substring(with: match.range(at: 1))

            guard let link = extractXMLValue(tag: "link", from: block)
                          ?? extractXMLValue(tag: "guid", from: block) else { continue }

            if let transcriptURL = extractAttr("url", from: block, context: "podcast:transcript"),
               let transcriptType = extractAttr("type", from: block, context: "podcast:transcript") {
                result[link] = (url: transcriptURL, formatRaw: transcriptType)
            }
        }
        return result
    }

    private static func extractXMLValue(tag: String, from block: String) -> String? {
        let pattern = "<\(tag)[^>]*>\\s*(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?\\s*</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: block, options: [], range: NSRange(block.startIndex..., in: block)),
              let range = Range(match.range(at: 1), in: block) else { return nil }
        let value = String(block[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractAttr(_ attr: String, from text: String, context: String) -> String? {
        let pattern = "<\(context)[^>]*\\b\(attr)=[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func extract(
        feed: Feed,
        feedType: FeedType,
        transcriptIndex: [String: (url: String, formatRaw: String)]
    ) -> [ParsedArticle] {
        switch feed {
        case .rss(let rss):
            return (rss.items ?? []).compactMap { item -> ParsedArticle? in
                guard let link = item.link, !link.isEmpty else { return nil }
                let desc = (item.description ?? item.content?.contentEncoded)
                    .map { stripHTML($0) }
                let transcriptInfo = transcriptIndex[link]
                return ParsedArticle(
                    url: link,
                    title: item.title ?? link,
                    publishedAt: item.pubDate ?? Date(),
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 },
                    isEpisode: feedType == .podcast,
                    transcriptURL: transcriptInfo?.url,
                    transcriptFormatRaw: transcriptInfo?.formatRaw
                )
            }
        case .atom(let atom):
            return (atom.entries ?? []).compactMap { entry -> ParsedArticle? in
                let link = entry.links?.first?.attributes?.href ?? ""
                guard !link.isEmpty else { return nil }
                let desc = (entry.summary?.value ?? entry.content?.value)
                    .map { stripHTML($0) }
                let transcriptInfo = transcriptIndex[link]
                return ParsedArticle(
                    url: link,
                    title: entry.title ?? link,
                    publishedAt: entry.published ?? entry.updated ?? Date(),
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 },
                    isEpisode: feedType == .podcast,
                    transcriptURL: transcriptInfo?.url,
                    transcriptFormatRaw: transcriptInfo?.formatRaw
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
                    feedDescription: desc.flatMap { $0.isEmpty ? nil : $0 },
                    isEpisode: false,
                    transcriptURL: nil,
                    transcriptFormatRaw: nil
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
