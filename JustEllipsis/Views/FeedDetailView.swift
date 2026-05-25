import SwiftUI
import SwiftData

struct FeedDetailView: View {
    let feed: RSSFeed

    @Environment(\.modelContext) private var context
    @Query private var articles: [RSSArticle]
    @Query private var queue: [QueuedLink]

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
            AppTheme.background.ignoresSafeArea()

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
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing fetched yet.")
                .font(AppTheme.sansSerif(16, weight: .medium))
                .foregroundStyle(AppTheme.heading)

            Text("Articles appear after the next fetch.")
                .font(AppTheme.sansSerif(14))
                .foregroundStyle(AppTheme.textFaint)
        }
    }

    // MARK: - Actions

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

    @State private var justAdded = false

    private var displaySummary: String? {
        if let s = article.summary, !s.isEmpty { return s }
        if let d = article.feedDescription, !d.isEmpty { return d }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(AppTheme.heading)
                    .lineLimit(2)

                if let summary = displaySummary {
                    Text(summary)
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(AppTheme.textFaint)
                        .lineLimit(2)
                }

                Text(article.publishedAt, style: .relative)
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(AppTheme.textFaint)
            }

            Spacer()

            if isQueued || justAdded {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.readerAccent)
                    .frame(width: 32, height: 32)
            } else {
                Button {
                    onAdd()
                    justAdded = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.heading)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .onChange(of: isQueued) { _, queued in
            // If the link was removed from the queue externally (deleted from HomeView
            // or read and later deleted from the Brain), clear the local justAdded flag
            // so the + button re-appears and the article can be re-added.
            if !queued { justAdded = false }
        }
    }
}
