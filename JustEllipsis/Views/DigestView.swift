import SwiftUI
import SwiftData

struct DigestView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Environment(GradingProgressTracker.self) private var gradingTracker

    @Query private var articles: [RSSArticle]
    @Query(filter: #Predicate<RSSFeed> { !$0.isArchived }) private var feeds: [RSSFeed]
    @Query private var queue: [QueuedLink]
    @Query(sort: \BrainEntry.readAt, order: .reverse) private var brainEntries: [BrainEntry]

    @AppStorage("streak.minReadsPerDay")  private var minReadsPerDay:       Int  = 1
    @AppStorage("grading.enabled")       private var gradingEnabled:        Bool = false
    @AppStorage("digest.hideNoise")      private var hideNoise:             Bool = false

    @State private var isFetching = false
    @State private var selectedTopic: String = "All"

    init() {
        let stored = UserDefaults.standard.object(forKey: RSSFetchService.retentionDaysKey) as? Int
        let days = stored ?? RSSFetchService.defaultRetentionDays
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: startOfToday) ?? startOfToday
        _articles = Query(
            filter: #Predicate<RSSArticle> { $0.publishedAt >= cutoff },
            sort: \RSSArticle.publishedAt,
            order: .reverse
        )
    }

    private var queuedURLs: Set<String> { Set(queue.map { $0.url }) }

    private var feedLookup: [UUID: RSSFeed] {
        Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
    }

    // Priority: AI topics → feed category → feed title (always non-empty for valid feeds).
    private func topicLabels(for article: RSSArticle) -> [String] {
        if !article.topics.isEmpty { return article.topics }
        guard let feed = feedLookup[article.feedID] else { return [] }
        if !feed.category.isEmpty { return [feed.category] }
        return feed.title.isEmpty ? [] : [feed.title]
    }

    private var availableTopics: [String] {
        let all = todayArticles + yesterdayArticles + earlierArticles
        var counts: [String: Int] = [:]
        for article in all {
            for label in topicLabels(for: article) {
                counts[label, default: 0] += 1
            }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(20).map(\.key)
        return ["All"] + top
    }

    private var todayArticles: [RSSArticle] {
        var seen = Set<String>()
        return articles
            .filter { feedLookup[$0.feedID] != nil }
            .filter { Calendar.current.isDateInToday($0.publishedAt) }
            .filter { seen.insert($0.url).inserted }
            .filter { !(gradingEnabled && hideNoise && $0.qualityGrade == .noise) }
    }

    private var yesterdayArticles: [RSSArticle] {
        var seen = Set<String>()
        return articles
            .filter { feedLookup[$0.feedID] != nil }
            .filter { Calendar.current.isDateInYesterday($0.publishedAt) }
            .filter { seen.insert($0.url).inserted }
            .filter { !(gradingEnabled && hideNoise && $0.qualityGrade == .noise) }
    }

    private var earlierArticles: [RSSArticle] {
        var seen = Set<String>()
        return articles
            .filter { feedLookup[$0.feedID] != nil }
            .filter {
                !Calendar.current.isDateInToday($0.publishedAt) &&
                !Calendar.current.isDateInYesterday($0.publishedAt)
            }
            .filter { seen.insert($0.url).inserted }
            .filter { !(gradingEnabled && hideNoise && $0.qualityGrade == .noise) }
    }

    private var brainURLs: Set<String> { Set(brainEntries.map { $0.url }) }

    // Returns nil when the Brain doesn't yet have enough signal (< 5 entries).
    private var recommendations: [RSSArticle]? {
        guard brainEntries.count >= 5 else { return nil }

        let candidates = articles.filter {
            feedLookup[$0.feedID] != nil &&
            !queuedURLs.contains($0.url) &&
            !brainURLs.contains($0.url) &&
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
        return picks.isEmpty ? nil : picks
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

        // First pass: one per feed.
        for article in articles {
            guard picks.count < count else { break }
            if seen.insert(article.feedID).inserted { picks.append(article) }
        }

        // Second pass: fill remaining slots from any feed.
        if picks.count < count {
            let pickIDs = Set(picks.map { $0.id })
            for article in articles where !pickIDs.contains(article.id) {
                guard picks.count < count else { break }
                picks.append(article)
            }
        }

        return picks
    }

    private enum DigestItem: Identifiable {
        case brainHeader
        case dateHeader(String)
        case article(RSSArticle)

        var id: String {
            switch self {
            case .brainHeader: return "header-brain"
            case .dateHeader(let label): return "header-\(label)"
            case .article(let a): return a.id.uuidString
            }
        }
    }

    private var digestItems: [DigestItem] {
        var items: [DigestItem] = []

        let topicMatch: (RSSArticle) -> Bool = { [self] article in
            guard selectedTopic != "All" else { return true }
            return topicLabels(for: article).contains(selectedTopic)
        }

        // Compute recommendations once; exclude those URLs from the date sections
        // so each article appears in exactly one place.
        let recs = recommendations?.filter(topicMatch)
        let recURLs: Set<String> = recs.map { Set($0.map { $0.url }) } ?? []

        if let recs, !recs.isEmpty {
            items.append(.brainHeader)
            items.append(contentsOf: recs.map { .article($0) })
        }

        let today = todayArticles.filter { !recURLs.contains($0.url) }.filter(topicMatch)
        if !today.isEmpty {
            items.append(.dateHeader("TODAY"))
            items.append(contentsOf: today.map { .article($0) })
        }

        let yesterday = yesterdayArticles.filter { !recURLs.contains($0.url) }.filter(topicMatch)
        if !yesterday.isEmpty {
            items.append(.dateHeader("YESTERDAY"))
            items.append(contentsOf: yesterday.map { .article($0) })
        }

        let earlier = earlierArticles.filter { !recURLs.contains($0.url) }.filter(topicMatch)
        if !earlier.isEmpty {
            items.append(.dateHeader("EARLIER"))
            items.append(contentsOf: earlier.map { .article($0) })
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if availableTopics.count > 1 {
                        topicFilterBar
                    }

                    if articles.isEmpty {
                        emptyState
                    } else if digestItems.isEmpty {
                        filteredEmptyState
                    } else {
                        digestList
                    }
                }
            }
            .navigationTitle("Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refetch()
                    } label: {
                        if isFetching {
                            ProgressView()
                                .tint(appTheme.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(appTheme.accent)
                        }
                    }
                    .disabled(isFetching)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onChange(of: availableTopics) { _, newTopics in
                if !newTopics.contains(selectedTopic) { selectedTopic = "All" }
            }
        }
    }

    private var digestList: some View {
        List {
            ForEach(digestItems) { item in
                switch item {
                case .brainHeader:
                    brainDivider
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: 16,
                            leading: AppTheme.pagePadding,
                            bottom: 4,
                            trailing: AppTheme.pagePadding
                        ))
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
                case .article(let article):
                    DigestArticleRow(
                        article: article,
                        feedName: feedLookup[article.feedID]?.title ?? "",
                        isQueued: queuedURLs.contains(article.url)
                    ) {
                        addToQueue(article)
                    }
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
    }

    private func refetch() {
        guard !isFetching else { return }
        isFetching = true
        selectedTopic = "All"
        let task = RSSFetchService.fetchInProcess(container: context.container, tracker: gradingTracker)
        Task {
            await task.value
            await MainActor.run { isFetching = false }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing from the past week.")
                .font(AppTheme.sansSerif(16, weight: .medium))
                .foregroundStyle(appTheme.heading)

            Text("New articles will appear here after the next fetch.")
                .font(AppTheme.sansSerif(14))
                .foregroundStyle(appTheme.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private var topicFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableTopics, id: \.self) { topic in
                    Button {
                        selectedTopic = topic
                    } label: {
                        Text(topic)
                            .font(AppTheme.sansSerif(13, weight: selectedTopic == topic ? .semibold : .regular))
                            .foregroundStyle(selectedTopic == topic ? appTheme.background : appTheme.textFaint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedTopic == topic ? appTheme.accent : appTheme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
        .padding(.vertical, 10)
        .background(appTheme.background)
    }

    private var filteredEmptyState: some View {
        Spacer()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Text("Nothing here.")
                    .font(AppTheme.sansSerif(15))
                    .foregroundStyle(appTheme.textFaint)
            )
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
}

// MARK: - Article row

private struct DigestArticleRow: View {
    let article: RSSArticle
    let feedName: String
    let isQueued: Bool
    let onAdd: () -> Void

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
            FaviconView(domain: domain)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.heading)
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

            if isQueued || justAdded {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
                    .frame(width: 32, height: 32)
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
