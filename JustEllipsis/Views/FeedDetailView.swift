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
    @State private var confirmSafariURL: URL? = nil
    @State private var pendingConfirmArticle: RSSArticle? = nil

    init(feed: RSSFeed) {
        self.feed = feed
        let feedID = feed.id
        let stored = UserDefaults.standard.object(forKey: RSSFetchService.retentionDaysKey) as? Int
        let retentionDays = stored ?? RSSFetchService.defaultRetentionDays
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let cutoff: Date
        switch feed.feedType {
        case .scraped:
            cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: startOfToday) ?? startOfToday
        case .newsletter:
            cutoff = Calendar.current.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
        case .rss:
            cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: startOfToday) ?? startOfToday
        }
        _articles = Query(
            filter: #Predicate<RSSArticle> {
                $0.feedID == feedID &&
                $0.publishedAt >= cutoff &&
                $0.isConfirmationDismissed == false
            },
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
                    // Last read card — always shown above articles
                    Section {
                        LastReadCard(lastReadAt: feed.lastReadAt)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: 8,
                                leading: AppTheme.pagePadding,
                                bottom: 4,
                                trailing: AppTheme.pagePadding
                            ))
                    }
                    .listSectionSeparator(.hidden)

                    // Reading address — shown at the top of newsletter feeds
                    if feed.feedType == .newsletter, let email = feed.newsletterEmail {
                        Section {
                            NewsletterAddressRow(email: email)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 5,
                                    leading: AppTheme.pagePadding,
                                    bottom: 5,
                                    trailing: AppTheme.pagePadding
                                ))
                        } header: {
                            Text("YOUR READING ADDRESS")
                                .font(AppTheme.sansSerif(11, weight: .medium))
                                .foregroundStyle(appTheme.accent)
                                .kerning(2)
                                .textCase(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.pagePadding)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                    }

                    Section {
                        ForEach(articles) { article in
                            if isConfirmationEmail(article) {
                                ConfirmationArticleRow(article: article, onOpen: {
                                    openConfirmation(article)
                                })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 5,
                                    leading: AppTheme.pagePadding,
                                    bottom: 5,
                                    trailing: AppTheme.pagePadding
                                ))
                            } else {
                                ArticleRow(
                                    article: article,
                                    isQueued: queuedURLs.contains(article.url),
                                    onAdd: { addToQueue(article) },
                                    onRemove: { removeFromQueue(article) }
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
                    } header: {
                        if feed.feedType == .scraped {
                            Text("Web feed — dates may be approximate.")
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)
                                .textCase(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.pagePadding)
                                .padding(.vertical, 6)
                        }
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
                    feed.isFavourite.toggle()
                    try? context.save()
                } label: {
                    Image(systemName: feed.isFavourite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                }
            }
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
        .sheet(item: $confirmSafariURL, onDismiss: {
            if let article = pendingConfirmArticle {
                article.isConfirmationDismissed = true
                try? context.save()
                pendingConfirmArticle = nil
            }
        }) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            if feed.feedType == .newsletter {
                Text("Waiting for first edition.")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("New editions appear here automatically.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)

                if let email = feed.newsletterEmail {
                    NewsletterAddressRow(email: email)
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.top, 8)
                }
            } else {
                Text("Nothing fetched yet.")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("Articles appear after the next fetch.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
            }
        }
    }

    // MARK: - Actions

    private func isConfirmationEmail(_ article: RSSArticle) -> Bool {
        guard feed.feedType == .newsletter else { return false }
        let title = article.title.lowercased()
        let body  = (article.feedDescription ?? "").lowercased()

        // Subject lines that directly name the action
        let titleKeywords = ["confirm", "verify", "activate your", "double opt"]
        if titleKeywords.contains(where: { title.contains($0) }) { return true }

        // Body phrases — specific enough to avoid false positives on regular content.
        // "confirm email" catches button labels like "CONFIRM EMAIL" (lowercased).
        // "confirm your opt" catches "confirm your opt-in" used by many ESPs.
        let bodyPhrases = [
            "confirm your subscription", "confirm your email", "confirm your address",
            "confirm your opt", "confirm opt-in", "confirm email",
            "verify your email", "verify your subscription",
            "click to confirm", "click to verify",
            "complete your subscription", "activate your subscription",
            "double opt-in"
        ]
        return bodyPhrases.contains(where: { body.contains($0) })
    }

    private func openConfirmation(_ article: RSSArticle) {
        guard let url = URL(string: article.url) else { return }
        pendingConfirmArticle = article
        confirmSafariURL = url
    }

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

    private func removeFromQueue(_ article: RSSArticle) {
        guard let link = queue.first(where: { $0.url == article.url }) else { return }
        article.isQueued = false
        context.delete(link)
        try? context.save()
    }
}

// MARK: - Last read card

private struct LastReadCard: View {
    let lastReadAt: Date?
    @Environment(\.appTheme) private var appTheme

    private var dateLabel: String {
        guard let date = lastReadAt else { return "Never" }
        return date.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("LAST READ")
                    .font(AppTheme.sansSerif(11, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                    .kerning(2)

                Text(dateLabel)
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(lastReadAt != nil ? appTheme.heading : appTheme.textFaint)
            }
            Spacer()
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(appTheme.separator, lineWidth: 1)
        )
    }
}

// MARK: - Newsletter address row

private struct NewsletterAddressRow: View {
    let email: String

    @Environment(\.appTheme) private var appTheme
    @State private var justCopied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = email
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                justCopied = false
            }
        } label: {
            HStack(spacing: 12) {
                Text(email)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(justCopied ? appTheme.accent : appTheme.textFaint)
                    .animation(.easeInOut(duration: 0.15), value: justCopied)
            }
            .padding(AppTheme.cardPadding)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Article row

private struct ArticleRow: View {
    let article: RSSArticle
    let isQueued: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

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
                TitleWithRewriteIndicator(
                    displayTitle: article.displayTitle,
                    originalTitle: article.hasRewrite ? article.title : nil,
                    font: AppTheme.sansSerif(14, weight: .medium)
                )
                .lineLimit(titleLineLimit)

                if let summary = displaySummary {
                    Text(summary)
                        .font(AppTheme.sansSerif(13, weight: .medium))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(summaryLineLimit)
                        .lineSpacing(2)
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
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appTheme.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
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

// MARK: - Confirmation article row

private struct ConfirmationArticleRow: View {
    let article: RSSArticle
    let onOpen: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(3)

                Text("Open to confirm your subscription.")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                    .lineSpacing(2)

                Text(article.publishedAt.relativeShort)
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
            }

            Spacer()

            Button {
                onOpen()
            } label: {
                Text("Open")
                    .font(AppTheme.sansSerif(12, weight: .semibold))
                    .foregroundStyle(appTheme.background)
                    .frame(width: 60, height: 30)
                    .background(appTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(appTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}
