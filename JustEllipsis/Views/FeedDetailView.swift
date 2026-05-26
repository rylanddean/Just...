import SwiftUI
import SwiftData

struct FeedDetailView: View {
    let feed: RSSFeed

    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @Query private var articles: [RSSArticle]
    @Query private var queue: [QueuedLink]

    @State private var isFetching = false

    init(feed: RSSFeed) {
        self.feed = feed
        let feedID = feed.id
        _articles = Query(
            filter: #Predicate<RSSArticle> { $0.feedID == feedID },
            sort: \RSSArticle.publishedAt,
            order: .reverse
        )
    }

    private var queuedURLs: Set<String> { Set(queue.map { $0.url }) }

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            if articles.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(articles) { article in
                        ArticleRow(article: article, isQueued: queuedURLs.contains(article.url)) {
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 32, for: .scrollContent)
            }
        }
        .navigationTitle(feed.title)
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing fetched yet.")
                .font(AppTheme.sansSerif(16, weight: .medium))
                .foregroundStyle(appTheme.heading)

            Text("Articles appear after the next fetch.")
                .font(AppTheme.sansSerif(14))
                .foregroundStyle(appTheme.textFaint)
        }
    }

    // MARK: - Actions

    private func refetch() {
        guard !isFetching else { return }
        isFetching = true
        RSSFetchService.fetchSingle(feedID: feed.id, url: feed.url, container: context.container, tracker: gradingTracker)
        Task {
            try? await Task.sleep(for: .seconds(2))
            isFetching = false
        }
    }

    private func addToQueue(_ article: RSSArticle) {
        guard !queuedURLs.contains(article.url) else { return }
        let maxOrder = queue.map { $0.sortOrder }.max() ?? -1
        let link = QueuedLink(
            url: article.url,
            sortOrder: maxOrder + 1,
            title: article.title,
            source: .rss(feedID: feed.id)
        )
        context.insert(link)
        article.isQueued = true
        try? context.save()
    }
}

// MARK: - Article row

private struct ArticleRow: View {
    let article: RSSArticle
    let isQueued: Bool
    let onAdd: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @State private var justAdded = false

    private var displaySummary: String? {
        if let s = article.summary, !s.isEmpty { return s }
        if let d = article.feedDescription, !d.isEmpty { return d }
        return nil
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
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(2)

                if let summary = displaySummary {
                    Text(summary)
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(article.publishedAt.relativeShort)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)

                    if let mins = article.estimatedReadingMinutes {
                        Text("·")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                        Text("\(mins) min")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    }

                    if gradingTracker.activeIDs.contains(article.id) || article.qualityGrade != nil {
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
