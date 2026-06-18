import SwiftUI
import SwiftData

struct DigestView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Environment(GradingProgressTracker.self)  private var gradingTracker
    @Environment(PipelineProgressTracker.self) private var pipelineTracker

    @StateObject private var weatherService = DigestWeatherService.shared

    @Query(sort: \RSSArticle.publishedAt, order: .reverse) private var articles: [RSSArticle]
    @Query(filter: #Predicate<RSSFeed> { !$0.isArchived }) private var feeds: [RSSFeed]
    @Query private var queue: [QueuedLink]
    @Query(sort: \BrainEntry.readAt, order: .reverse) private var brainEntries: [BrainEntry]

    @AppStorage("streak.minReadsPerDay")              private var minReadsPerDay:    Int  = 1
    @AppStorage("grading.enabled")                    private var gradingEnabled:    Bool = false
    @AppStorage("digest.hideNoise")                   private var hideNoise:         Bool = false
    @AppStorage("digest.hideSeen")                    private var hideSeen:          Bool = false
    @AppStorage(RSSFetchService.retentionDaysKey)     private var retentionDays:     Int  = RSSFetchService.defaultRetentionDays
    @AppStorage("digest.brainMode")                   private var brainMode:         Bool = false

    @Environment(DigestRelevanceStore.self) private var relevanceStore

    private var retentionLabel: String {
        switch retentionDays {
        case 1:  return "the past day"
        case 7:  return "the past week"
        default: return "the past \(retentionDays) days"
        }
    }

    @State private var isProcessing = false
    @State private var selectedTopic: String = "All"
    @State private var hiddenSeenIDs: Set<UUID> = []
    @State private var activeDigestArticle: RSSArticle?
    @State private var showingFilters = false

    private var hasEnoughBrain: Bool {
        brainEntries.filter { $0.dna != nil }.count >= 5
    }

    private var isFilterActive: Bool {
        hideSeen || (gradingEnabled && hideNoise) || brainMode || selectedTopic != "All"
    }

    // Non-@Observable helpers — mutations don't trigger SwiftUI re-renders.
    @State private var seenBatcher     = SeenBatcher()
    @State private var recCache        = RecommendationCache()

    // MARK: - Pre-computed lookup (cheap, rebuilt only when feeds change)

    private var feedLookup: [UUID: RSSFeed] {
        Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
    }

    private var queuedURLs: Set<String> { Set(queue.map { $0.url }) }

    // MARK: - Single-pass bucketing

    private struct ArticleBuckets {
        let today: [RSSArticle]
        let yesterday: [RSSArticle]
        let earlier: [RSSArticle]
        let scraped: [(feed: RSSFeed, articles: [RSSArticle])]
        let topics: [String]
        let hasUntagged: Bool
        /// True when at least one article is within the retention window and belongs to a known feed,
        /// regardless of isRead / hideSeen / topic filters. Drives the empty-state branch.
        let inWindow: Bool
    }

    /// Scans `articles` exactly once, producing date buckets, topic counts, and untagged flag.
    private func buildBuckets() -> ArticleBuckets {
        let lookup = feedLookup
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: startOfToday) ?? startOfToday
        guard let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday) else {
            return ArticleBuckets(today: [], yesterday: [], earlier: [], scraped: [], topics: ["All"], hasUntagged: false, inWindow: false)
        }

        var todayDedupe = Set<String>()
        var yesterdayDedupe = Set<String>()
        var earlierDedupe = Set<String>()
        var todayList:        [RSSArticle] = []
        var yesterdayList:    [RSSArticle] = []
        var earlierList:      [RSSArticle] = []
        var scrapedByFeedID:  [UUID: [RSSArticle]] = [:]
        var topicCounts:      [String: Int] = [:]
        var hasUntagged = false
        var inWindow = false

        for article in articles {
            guard article.publishedAt >= cutoff else { continue }
            guard lookup[article.feedID] != nil else { continue }
            inWindow = true
            if article.isRead == true { continue }
            if gradingEnabled && hideNoise && article.qualityGrade == .noise { continue }
            if hiddenSeenIDs.contains(article.id) { continue }

            if article.topics.isEmpty {
                hasUntagged = true
            } else {
                for topic in article.topics { topicCounts[topic, default: 0] += 1 }
            }

            if lookup[article.feedID]?.feedType == .scraped {
                scrapedByFeedID[article.feedID, default: []].append(article)
                continue
            }

            if article.publishedAt >= startOfToday {
                if todayDedupe.insert(article.url).inserted { todayList.append(article) }
            } else if article.publishedAt >= startOfYesterday {
                if yesterdayDedupe.insert(article.url).inserted { yesterdayList.append(article) }
            } else {
                if earlierDedupe.insert(article.url).inserted { earlierList.append(article) }
            }
        }

        let scrapedSections = scrapedByFeedID
            .compactMap { feedID, articles -> (RSSFeed, [RSSArticle])? in
                guard let feed = lookup[feedID] else { return nil }
                return (feed, articles)
            }
            .sorted { $0.0.title < $1.0.title }

        let topTopics = topicCounts.sorted { $0.value > $1.value }.prefix(10).map(\.key)
        return ArticleBuckets(
            today: todayList,
            yesterday: yesterdayList,
            earlier: earlierList,
            scraped: scrapedSections,
            topics: ["All"] + topTopics,
            hasUntagged: hasUntagged,
            inWindow: inWindow
        )
    }

    // MARK: - Brain Ranking

    private func ranked(_ articles: [RSSArticle]) -> [RSSArticle] {
        guard brainMode else { return articles }
        return articles.sorted { a, b in
            let sa = relevanceStore.score(for: a.id)
            let sb = relevanceStore.score(for: b.id)
            if sa != sb { return sa > sb }
            return a.publishedAt > b.publishedAt
        }
    }

    private func triggerScoring() {
        guard brainMode else { return }
        let concepts = BrainViewModel.recentConcepts(entries: Array(brainEntries))
        relevanceStore.computeScores(for: Array(articles), concepts: concepts)
    }

    // MARK: - Recommendations

    // Returns nil when the Brain doesn't yet have enough signal (< 5 entries).
    private var recommendations: [RSSArticle]? {
        guard brainEntries.count >= 5 else { return nil }

        // Cache check — skip the expensive computation if inputs haven't changed.
        let cacheKey = RecommendationCache.Key(
            articleCount:  articles.count,
            brainCount:    brainEntries.count,
            queueCount:    queue.count,
            gradingEnabled: gradingEnabled,
            hideNoise:     hideNoise,
            minReadsPerDay: minReadsPerDay,
            retentionDays:  retentionDays
        )
        if cacheKey == recCache.key { return recCache.result }

        // Pre-compute lookup sets once — NOT inside the filter closure.
        let lookup     = feedLookup
        let queuedSet  = Set(queue.map { $0.url })
        let brainSet   = Set(brainEntries.map { $0.url })

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let candidates = articles.filter {
            $0.publishedAt >= cutoff &&
            lookup[$0.feedID] != nil &&
            $0.isRead != true &&
            !queuedSet.contains($0.url) &&
            !brainSet.contains($0.url) &&
            !(gradingEnabled && hideNoise && $0.qualityGrade == .noise)
        }
        guard !candidates.isEmpty else { return nil }

        let keywords = brainKeywords()
        let scored: [RSSArticle]
        if keywords.isEmpty {
            scored = candidates.sorted { $0.publishedAt > $1.publishedAt }
        } else {
            scored = candidates
                .map { article -> (RSSArticle, Int) in
                    let words = Set(article.title.lowercased().split(separator: " ").map(String.init))
                    return (article, words.intersection(keywords).count)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }

        let picks = diversifiedPicks(from: scored, max: minReadsPerDay)
        let result: [RSSArticle]? = picks.isEmpty ? nil : picks
        recCache.key    = cacheKey
        recCache.result = result
        return result
    }

    private func brainKeywords() -> Set<String> {
        let stopwords: Set<String> = [
            "the","a","an","and","or","but","in","on","at","to","for","of","with",
            "is","it","this","that","was","are","be","been","have","has","had",
            "do","did","will","would","could","should","may","might","can","not",
            "no","from","by","as","if","what","how","why","when","which","who",
            "than","more","about","i","my","me","we","our","you","your","its","how"
        ]
        var words = Set<String>()
        for entry in brainEntries.prefix(30) {
            entry.title.lowercased().split(separator: " ").forEach { words.insert(String($0)) }
            if let r = entry.reflection, !r.isEmpty {
                r.lowercased().split(separator: " ").forEach { words.insert(String($0)) }
            }
        }
        return words.filter { $0.count > 3 && !stopwords.contains($0) }
    }

    private func diversifiedPicks(from articles: [RSSArticle], max count: Int) -> [RSSArticle] {
        var seen = Set<UUID>()
        var picks: [RSSArticle] = []

        for article in articles {
            guard picks.count < count else { break }
            if seen.insert(article.feedID).inserted { picks.append(article) }
        }

        if picks.count < count {
            let pickIDs = Set(picks.map { $0.id })
            for article in articles where !pickIDs.contains(article.id) {
                guard picks.count < count else { break }
                picks.append(article)
            }
        }

        return picks
    }

    // MARK: - Digest items (uses pre-built buckets — no additional article scan)

    private enum DigestItem: Identifiable {
        case brainCarousel([RSSArticle])
        case dateHeader(String)
        case feedGroupHeader(String)
        case article(RSSArticle)

        var id: String {
            switch self {
            case .brainCarousel: return "carousel-brain"
            case .dateHeader(let label): return "header-\(label)"
            case .feedGroupHeader(let name): return "feedgroup-\(name)"
            case .article(let a): return a.id.uuidString
            }
        }
    }

    private func buildDigestItems(from buckets: ArticleBuckets) -> [DigestItem] {
        var items: [DigestItem] = []

        let topicMatch: (RSSArticle) -> Bool = { [self] article in
            guard selectedTopic != "All" else { return true }
            return article.topics.contains(selectedTopic)
        }

        let focusFilter: (RSSArticle) -> Bool = { [self] article in
            guard brainMode && hasEnoughBrain else { return true }
            return relevanceStore.score(for: article.id) > 0
        }

        let recs = recommendations?.filter(topicMatch)
        let recURLs: Set<String> = recs.map { Set($0.map(\.url)) } ?? []

        if let recs, !recs.isEmpty, !brainMode {
            items.append(.brainCarousel(recs))
        }

        let today = ranked(buckets.today.filter { !recURLs.contains($0.url) && topicMatch($0) && focusFilter($0) })
        if !today.isEmpty {
            items.append(.dateHeader("TODAY"))
            items.append(contentsOf: today.map { .article($0) })
        }

        let yesterday = ranked(buckets.yesterday.filter { !recURLs.contains($0.url) && topicMatch($0) && focusFilter($0) })
        if !yesterday.isEmpty {
            items.append(.dateHeader("YESTERDAY"))
            items.append(contentsOf: yesterday.map { .article($0) })
        }

        let earlier = ranked(buckets.earlier.filter { !recURLs.contains($0.url) && topicMatch($0) && focusFilter($0) })
        if !earlier.isEmpty {
            items.append(.dateHeader("EARLIER"))
            items.append(contentsOf: earlier.map { .article($0) })
        }

        let scrapedSections = buckets.scraped.compactMap { feed, articles -> (RSSFeed, [RSSArticle])? in
            let filtered = articles.filter { !recURLs.contains($0.url) && topicMatch($0) && focusFilter($0) }
            return filtered.isEmpty ? nil : (feed, filtered)
        }
        if !scrapedSections.isEmpty {
            items.append(.dateHeader("WEBSITES"))
            for (feed, articles) in scrapedSections {
                if scrapedSections.count > 1 {
                    items.append(.feedGroupHeader(feed.title))
                }
                items.append(contentsOf: articles.map { .article($0) })
            }
        }

        return items
    }

    // MARK: - Body

    var body: some View {
        // Computed once per body evaluation — single pass through articles.
        let buckets = buildBuckets()
        let items   = buildDigestItems(from: buckets)

        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let weather = weatherService.weather {
                        DigestWeatherCard(weather: weather)
                            .padding(.horizontal, AppTheme.pagePadding)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }

                    if !buckets.inWindow {
                        emptyState
                    } else if items.isEmpty && brainMode {
                        brainModeEmptyState
                    } else if items.isEmpty && hideSeen && selectedTopic == "All" {
                        seenCompleteState
                    } else if items.isEmpty {
                        filteredEmptyState
                    } else {
                        digestList(items)
                    }
                }
            }
            .navigationTitle("Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isFilterActive ? appTheme.accent : appTheme.textFaint)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        triggerProcessing()
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .tint(appTheme.accent)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(appTheme.accent)
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onChange(of: buckets.topics) { _, newTopics in
                if !newTopics.contains(selectedTopic) { selectedTopic = "All" }
            }
            .task(id: hideSeen) {
                hiddenSeenIDs = hideSeen
                    ? Set(articles.filter { $0.isSeen }.map { $0.id })
                    : []
            }
            .task {
                weatherService.refresh()
            }
            .task {
                guard articles.isEmpty, !isProcessing else { return }
                await refetch()
            }
            .fullScreenCover(item: $activeDigestArticle) { article in
                let source: ReadingSource = {
                    if let link = queue.first(where: { $0.url == article.url }) {
                        return .queued(link)
                    }
                    let d = URL(string: article.url).map { ContentFetcher.extractDomain(from: $0) } ?? article.url
                    return .digest(url: article.url, title: article.title, domain: d, feedID: article.feedID)
                }()
                ReaderView(source: source)
            }
            .onAppear { triggerScoring() }
            .onChange(of: brainMode) { _, enabled in
                guard enabled else { return }
                triggerScoring()
            }
            .onChange(of: articles.count) { _, _ in triggerScoring() }
            .sheet(isPresented: $showingFilters) {
                DigestFilterSheet(
                    hideSeen: $hideSeen,
                    hideNoise: $hideNoise,
                    brainMode: $brainMode,
                    selectedTopic: $selectedTopic,
                    topics: buckets.topics,
                    hasUntagged: buckets.hasUntagged,
                    gradingEnabled: gradingEnabled,
                    hasEnoughBrain: hasEnoughBrain,
                    onBrainModeEnabled: triggerScoring,
                    onDismiss: { showingFilters = false }
                )
            }
        }
    }

    // MARK: - Digest list

    private func digestList(_ items: [DigestItem]) -> some View {
        let lookup = feedLookup
        return List {
            ForEach(items) { item in
                switch item {
                case .brainCarousel(let recs):
                    brainCarousel(recs, lookup: lookup)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                case .dateHeader(let label):
                    dateDivider(label)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: 16,
                            leading: AppTheme.pagePadding,
                            bottom: 4,
                            trailing: AppTheme.pagePadding
                        ))
                case .feedGroupHeader(let name):
                    feedGroupDivider(name)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: 12,
                            leading: AppTheme.pagePadding,
                            bottom: 4,
                            trailing: AppTheme.pagePadding
                        ))
                case .article(let article):
                    DigestArticleRow(
                        article: article,
                        feedName: lookup[article.feedID]?.title ?? "",
                        isQueued: queuedURLs.contains(article.url),
                        onAdd: { addToQueue(article) },
                        onRemove: { removeFromQueue(article) },
                        onSeen: { seenBatcher.enqueue(article) },
                        onRead: { activeDigestArticle = article }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: 5,
                        leading: AppTheme.pagePadding,
                        bottom: 5,
                        trailing: AppTheme.pagePadding
                    ))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .refreshable { await refetch() }
        .tint(appTheme.accent)
    }

    // MARK: - Brain carousel

    private func brainCarousel(_ recs: [RSSArticle], lookup: [UUID: RSSFeed]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            brainDivider
                .padding(.horizontal, AppTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(recs) { article in
                        BrainRecommendationCard(
                            article: article,
                            feedName: lookup[article.feedID]?.title ?? "",
                            isQueued: queuedURLs.contains(article.url),
                            onAdd: { addToQueue(article) },
                            onRemove: { removeFromQueue(article) },
                            onRead: { activeDigestArticle = article }
                        )
                        .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
                    }
                }
                .padding(.leading, AppTheme.pagePadding)
                .padding(.trailing, AppTheme.pagePadding)
            }
        }
    }

    private func refetch() async {
        selectedTopic = "All"
        isProcessing = true
        let processingTask = await RSSFetchService.fetchForDisplay(
            container: context.container,
            tracker: gradingTracker,
            pipelineTracker: pipelineTracker
        )
        // Pull-to-refresh spinner stops here; processing continues in the background.
        // Track the task so the sparkles button stays in its loading state until done.
        Task { @MainActor in
            await processingTask.value
            isProcessing = false
        }
    }

    private func triggerProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        let container = context.container
        Task { @MainActor in
            await RSSFetchService.runPipeline(
                container: container,
                tracker: gradingTracker,
                pipelineTracker: pipelineTracker
            )
            isProcessing = false
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Nothing from \(retentionLabel).")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("Pull down to fetch new articles.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await refetch() }
        .tint(appTheme.accent)
    }

    private var seenCompleteState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("All read.")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("Nothing left to surface today.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await refetch() }
        .tint(appTheme.accent)
    }

    private var brainModeEmptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Nothing matched your Brain.")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("Your Brain hasn't encountered these articles yet.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await refetch() }
        .tint(appTheme.accent)
    }

    private var filteredEmptyState: some View {
        ScrollView {
            Text("Nothing here.")
                .font(AppTheme.sansSerif(15))
                .foregroundStyle(appTheme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .refreshable { await refetch() }
        .tint(appTheme.accent)
    }

    private var brainDivider: some View {
        HStack(spacing: 5) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10, weight: .semibold))
            Text("FROM YOUR BRAIN")
                .kerning(2)
        }
        .font(AppTheme.sansSerif(11, weight: .medium))
        .foregroundStyle(appTheme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateDivider(_ label: String) -> some View {
        Text(label)
            .font(AppTheme.sansSerif(11, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .kerning(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedGroupDivider(_ name: String) -> some View {
        Text(name.uppercased())
            .font(AppTheme.sansSerif(10, weight: .medium))
            .foregroundStyle(appTheme.textFaint.opacity(0.6))
            .kerning(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addToQueue(_ article: RSSArticle) {
        guard !queuedURLs.contains(article.url) else { return }
        let maxOrder = queue.map { $0.sortOrder }.max() ?? -1
        let link = QueuedLink(
            url: article.url,
            sortOrder: maxOrder + 1,
            title: article.title,
            source: .rss(feedID: article.feedID)
        )
        context.insert(link)
        article.isQueued = true
        try? context.save()
    }

    private func removeFromQueue(_ article: RSSArticle) {
        guard let link = queue.first(where: { $0.url == article.url }) else { return }
        article.isQueued = false
        context.delete(link)
        try? context.save()
    }
}

// MARK: - Seen batcher

/// Collects isSeen mutations and flushes them in one batch after scrolling settles.
/// Not @Observable, so mutations never trigger SwiftUI re-renders.
private final class SeenBatcher: @unchecked Sendable {
    private var pending:   [RSSArticle] = []
    private var flushTask: Task<Void, Never>?

    func enqueue(_ article: RSSArticle) {
        guard !article.isSeen, !pending.contains(where: { $0.id == article.id }) else { return }
        pending.append(article)
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.pending.forEach { $0.isSeen = true }
            self.pending.removeAll()
        }
    }
}

// MARK: - Recommendation cache

/// Caches the recommendations result so the expensive computation only reruns
/// when article count, brain size, queue, or grading settings actually change.
/// Not @Observable, so cache writes never trigger SwiftUI re-renders.
private final class RecommendationCache: @unchecked Sendable {
    struct Key: Equatable {
        let articleCount:   Int
        let brainCount:     Int
        let queueCount:     Int
        let gradingEnabled: Bool
        let hideNoise:      Bool
        let minReadsPerDay: Int
        let retentionDays:  Int
    }
    var key:    Key?             = nil
    var result: [RSSArticle]?    = nil
}

// MARK: - Brain recommendation card

private struct BrainRecommendationCard: View {
    let article: RSSArticle
    let feedName: String
    let isQueued: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onRead: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var justAdded = false

    private var domain: String {
        guard let url = URL(string: article.url) else { return "" }
        return ContentFetcher.extractDomain(from: url)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onRead()
            } label: {
                HStack(spacing: 10) {
                    FaviconView(domain: domain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(AppTheme.sansSerif(14, weight: .medium))
                            .foregroundStyle(appTheme.heading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

                        HStack(spacing: 6) {
                            if !feedName.isEmpty {
                                Text(feedName)
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                                    .lineLimit(1)
                                Text("·")
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                            }
                            Text(article.publishedAt.relativeShort)
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isQueued || justAdded {
                Button { onRemove() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appTheme.accent)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            } else {
                Button {
                    onAdd()
                    justAdded = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .frame(width: 30, height: 30)
                        .background(appTheme.background)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(appTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read later")
            }
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .onChange(of: isQueued) { _, queued in
            if !queued { justAdded = false }
        }
    }
}

// MARK: - Article row

private struct DigestArticleRow: View {
    let article: RSSArticle
    let feedName: String
    let isQueued: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onSeen: () -> Void
    let onRead: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @AppStorage("grading.enabled") private var gradingEnabled: Bool = false
    @State private var justAdded = false

    private var titleLineLimit: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 3 : 2
    }

    private var summaryLineLimit: Int {
        if UIDevice.current.userInterfaceIdiom == .phone { return 6 }
        return horizontalSizeClass == .regular ? 4 : 3
    }

    private var domain: String {
        guard let url = URL(string: article.url) else { return "" }
        return ContentFetcher.extractDomain(from: url)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onRead()
            } label: {
                HStack(spacing: 12) {
                    FaviconView(domain: domain)

                    VStack(alignment: .leading, spacing: 4) {
                        TitleWithRewriteIndicator(
                            displayTitle: article.displayTitle,
                            originalTitle: article.hasRewrite ? article.title : nil,
                            font: AppTheme.sansSerif(14, weight: .medium)
                        )
                        .foregroundStyle(article.isSeen ? appTheme.textFaint : appTheme.heading)
                        .lineLimit(titleLineLimit)

                        if let summary = article.summary ?? article.feedDescription, !summary.isEmpty {
                            Text(summary)
                                .font(AppTheme.sansSerif(13, weight: .medium))
                                .foregroundStyle(appTheme.textFaint)
                                .lineLimit(summaryLineLimit)
                                .lineSpacing(2)
                        }

                        HStack(spacing: 6) {
                            if !feedName.isEmpty {
                                Text(feedName)
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                                    .lineLimit(1)

                                Text("·")
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                            }

                            Text(article.publishedAt.relativeShort)
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)

                            if gradingEnabled &&
                                (gradingTracker.activeIDs.contains(article.id) || article.qualityGrade != nil) {
                                Text("·")
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                                ArticleGradeIndicator(articleID: article.id, grade: article.qualityGrade)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isQueued || justAdded {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appTheme.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from queue")
            } else {
                Button {
                    onAdd()
                    justAdded = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .frame(width: 32, height: 32)
                        .background(appTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(appTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read later")
            }
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .onDisappear { onSeen() }
        .onChange(of: isQueued) { _, queued in
            if !queued { justAdded = false }
        }
    }
}

// MARK: - Filter sheet

private struct DigestFilterSheet: View {
    @Binding var hideSeen: Bool
    @Binding var hideNoise: Bool
    @Binding var brainMode: Bool
    @Binding var selectedTopic: String

    let topics: [String]
    let hasUntagged: Bool
    let gradingEnabled: Bool
    let hasEnoughBrain: Bool
    let onBrainModeEnabled: () -> Void
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if IntelligenceService.isAvailable && hasEnoughBrain {
                        sectionHeader("BRAIN")
                        toggleRow("Brain Mode", subtitle: "Filter and rank by what your Brain knows.", isOn: $brainMode)
                            .onChange(of: brainMode) { _, on in if on { onBrainModeEnabled() } }
                        separator
                    }

                    sectionHeader("VISIBILITY")
                    toggleRow("Hide seen", isOn: $hideSeen)
                    if gradingEnabled && IntelligenceService.isAvailable {
                        separator
                        toggleRow("Hide noise", isOn: $hideNoise)
                    }

                    if topics.count > 1 || hasUntagged {
                        separator
                        sectionHeader("TOPICS")
                        if hasUntagged {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini).tint(appTheme.textFaint)
                                Text("Generating topics…")
                                    .font(AppTheme.sansSerif(13))
                                    .foregroundStyle(appTheme.textFaint)
                            }
                            .padding(.horizontal, AppTheme.pagePadding)
                            .padding(.vertical, 14)
                        } else {
                            ForEach(topics, id: \.self) { topic in
                                Button {
                                    selectedTopic = topic
                                } label: {
                                    HStack {
                                        Text(topic)
                                            .font(AppTheme.sansSerif(15))
                                            .foregroundStyle(appTheme.heading)
                                        Spacer()
                                        if selectedTopic == topic {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(appTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, AppTheme.pagePadding)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if topic != topics.last {
                                    separator
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(appTheme.background)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                }
            }
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(AppTheme.sansSerif(11, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .kerning(2)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func toggleRow(_ label: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(AppTheme.sansSerif(15))
                    .foregroundStyle(appTheme.heading)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(appTheme.accent)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
    }

    private var separator: some View {
        Divider()
            .background(appTheme.separator)
            .padding(.horizontal, AppTheme.pagePadding)
    }
}
