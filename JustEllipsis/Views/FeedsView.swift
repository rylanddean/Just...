import SwiftUI
import SwiftData

struct FeedsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Environment(AppRouter.self) private var router
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @Query(filter: #Predicate<RSSFeed> { !$0.isArchived }, sort: \RSSFeed.title) private var feeds: [RSSFeed]
    @Query(filter: #Predicate<RSSFeed> { $0.isArchived },  sort: \RSSFeed.title) private var archivedFeeds: [RSSFeed]

    @AppStorage("archivedFeedsSectionExpanded") private var archivedSectionExpanded: Bool = false

    @State private var showAddByURL = false
    @State private var showAddNewsletter = false
    @State private var showDirectory = false
    @State private var showNewsletterDirectory = false
    @State private var prefilledNewsletterURL = ""
    @State private var pasteURL = ""
    @State private var customFeedName = ""
    @State private var addError: String?
    @State private var isFetching = false
    @State private var feedToRename: RSSFeed?
    @State private var renameText = ""
    @State private var showRenameSheet = false
    @State private var detectedCategoryPreview: String?

    private static let feedCategoryOptions: [String] = {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in FeedDirectoryItem.loadAll() {
            if seen.insert(item.category).inserted {
                ordered.append(item.category)
            }
        }
        if seen.insert("General").inserted {
            ordered.append("General")
        }
        return ordered
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if feeds.isEmpty && archivedFeeds.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .navigationTitle("Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showDirectory = true
                        } label: {
                            Label("RSS Feeds", systemImage: "dot.radiowaves.left.and.right")
                        }
                        Button {
                            showNewsletterDirectory = true
                        } label: {
                            Label("Newsletters", systemImage: "newspaper")
                        }
                    } label: {
                        Text("Browse")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.accent)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            pasteURL = ""
                            customFeedName = ""
                            detectedCategoryPreview = nil
                            addError = nil
                            showAddByURL = true
                        } label: {
                            Label("RSS Feed", systemImage: "dot.radiowaves.left.and.right")
                        }
                        Button {
                            prefilledNewsletterURL = ""
                            showAddNewsletter = true
                        } label: {
                            Label("Newsletter", systemImage: "envelope")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(appTheme.accent)
                    }
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .sheet(isPresented: $showAddByURL) {
            addByURLSheet
        }
        .sheet(isPresented: $showAddNewsletter) {
            AddNewsletterSheet(prefilledURL: prefilledNewsletterURL) { feedURL, email, title in
                subscribeNewsletter(feedURL: feedURL, email: email, title: title)
            }
        }
        .sheet(isPresented: $showNewsletterDirectory) {
            NewsletterDirectoryView { item in
                prefilledNewsletterURL = item.url
                showAddNewsletter = true
            }
        }
        .sheet(isPresented: $showDirectory) {
            FeedDirectoryView(subscribedURLs: Set(feeds.map { $0.url })) { item in
                subscribe(url: item.url, title: item.name, category: item.category)
            }
        }
        .sheet(isPresented: $showRenameSheet, onDismiss: { feedToRename = nil }) {
            renameSheet
        }
        .onChange(of: router.pendingFeedURL) { _, pendingURL in
            guard let url = pendingURL else { return }
            pasteURL = url
            customFeedName = ""
            detectedCategoryPreview = nil
            addError = nil
            showAddByURL = true
            router.pendingFeedURL = nil
        }
    }

    // MARK: - Feed list

    private var feedList: some View {
        List {
            ForEach(feeds) { feed in
                NavigationLink(destination: FeedDetailView(feed: feed)) {
                    FeedRow(feed: feed)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 5,
                    leading: AppTheme.pagePadding,
                    bottom: 5,
                    trailing: AppTheme.pagePadding
                ))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        unsubscribe(feed)
                    } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                    .tint(AppTheme.danger)

                    Button {
                        archive(feed)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(appTheme.textFaint)
                }
                .contextMenu {
                    Button {
                        renameText = feed.title
                        feedToRename = feed
                        showRenameSheet = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    if feed.feedType == .newsletter, let email = feed.newsletterEmail {
                        Button {
                            UIPasteboard.general.string = email
                        } label: {
                            Label("Copy reading address", systemImage: "envelope")
                        }
                    } else {
                        Button {
                            UIPasteboard.general.string = feed.url
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                    }

                    if feed.isPaused {
                        Button {
                            feed.isPaused = false
                            try? context.save()
                        } label: {
                            Label("Resume", systemImage: "play.circle")
                        }
                    } else {
                        Button {
                            feed.isPaused = true
                            try? context.save()
                        } label: {
                            Label("Pause", systemImage: "pause.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        unsubscribe(feed)
                    } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
            // Archived feeds section — collapsed by default, absent when nothing is archived
            if !archivedFeeds.isEmpty {
                Section {
                    DisclosureGroup(
                        isExpanded: $archivedSectionExpanded,
                        content: {
                            ForEach(archivedFeeds) { feed in
                                ArchivedFeedRow(feed: feed, onRestore: { restore(feed) })
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(
                                        top: 4,
                                        leading: AppTheme.pagePadding,
                                        bottom: 4,
                                        trailing: AppTheme.pagePadding
                                    ))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            unsubscribe(feed)
                                        } label: {
                                            Label("Unsubscribe", systemImage: "trash")
                                        }
                                        .tint(AppTheme.danger)
                                    }
                            }
                        },
                        label: {
                            HStack(spacing: 6) {
                                Text("ARCHIVED FEEDS")
                                    .font(AppTheme.sansSerif(11, weight: .medium))
                                    .foregroundStyle(appTheme.textFaint)
                                    .kerning(2)
                                Text("(\(archivedFeeds.count))")
                                    .font(AppTheme.sansSerif(11, weight: .medium))
                                    .foregroundStyle(appTheme.textFaint.opacity(0.6))
                                    .kerning(2)
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: 12,
                        leading: AppTheme.pagePadding,
                        bottom: 4,
                        trailing: AppTheme.pagePadding
                    ))
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 32, for: .scrollContent)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Text("Nothing subscribed.")
                    .font(AppTheme.sansSerif(18, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("Browse feeds or add a URL.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showDirectory = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Browse feeds")
                            .font(AppTheme.sansSerif(15, weight: .semibold))
                            .foregroundStyle(appTheme.background)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(appTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    pasteURL = ""
                    customFeedName = ""
                    detectedCategoryPreview = nil
                    addError = nil
                    showAddByURL = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Add a URL")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.textFaint)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(appTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(appTheme.separator, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Add by URL sheet

    private var addByURLSheet: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FEED URL")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(2)

                        TextField("https://example.com/feed.xml", text: $pasteURL)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.heading)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .padding(AppTheme.cardPadding)
                            .background(appTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM NAME (OPTIONAL)")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(2)

                        TextField("Leave blank to use the feed's title", text: $customFeedName)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.heading)
                            .padding(AppTheme.cardPadding)
                            .background(appTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CATEGORY")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(2)

                        Text(detectedCategoryPreview ?? "Auto-detected with Apple Intelligence")
                            .font(AppTheme.sansSerif(13))
                            .foregroundStyle(detectedCategoryPreview == nil ? appTheme.textFaint : appTheme.heading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.cardPadding)
                            .background(appTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    if let error = addError {
                        Text(error)
                            .font(AppTheme.sansSerif(13))
                            .foregroundStyle(AppTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await addFromURL() }
                    } label: {
                        HStack {
                            Spacer()
                            if isFetching {
                                ProgressView()
                                    .tint(appTheme.background)
                            } else {
                                Text("Add feed")
                                    .font(AppTheme.sansSerif(15, weight: .semibold))
                                    .foregroundStyle(appTheme.background)
                            }
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(pasteURL.isEmpty ? appTheme.accentFaint : appTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(pasteURL.isEmpty || isFetching)

                    Spacer()
                }
                .padding(AppTheme.pagePadding)
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddByURL = false }
                        .foregroundStyle(appTheme.accent)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Rename sheet

    private var renameSheet: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FEED NAME")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(2)

                        TextField("Feed name", text: $renameText)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.heading)
                            .padding(AppTheme.cardPadding)
                            .background(appTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        if let feed = feedToRename, !trimmed.isEmpty {
                            feed.title = trimmed
                            try? context.save()
                        }
                        showRenameSheet = false
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save")
                                .font(AppTheme.sansSerif(15, weight: .semibold))
                                .foregroundStyle(appTheme.background)
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(trimmed.isEmpty ? appTheme.accentFaint : appTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)

                    Spacer()
                }
                .padding(AppTheme.pagePadding)
            }
            .navigationTitle("Rename Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameSheet = false }
                        .foregroundStyle(appTheme.accent)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func subscribe(url: String, title: String, category: String) {
        guard !feeds.contains(where: { $0.url == url }) else { return }
        let feed = RSSFeed(url: url, title: title, category: category)
        context.insert(feed)
        try? context.save()
        RSSFetchService.fetchSingle(feedID: feed.id, url: url, container: context.container, tracker: gradingTracker)
    }

    private func subscribeNewsletter(feedURL: String, email: String, title: String) {
        guard !feeds.contains(where: { $0.url == feedURL }) else { return }
        let feed = RSSFeed(url: feedURL, title: title, category: "Newsletter")
        feed.feedType = .newsletter
        feed.newsletterEmail = email
        context.insert(feed)
        try? context.save()
        RSSFetchService.fetchSingle(feedID: feed.id, url: feedURL, container: context.container, tracker: gradingTracker)
    }

    private func archive(_ feed: RSSFeed) {
        feed.isArchived = true
        feed.archiveReason = "manual"
        try? context.save()
    }

    private func restore(_ feed: RSSFeed) {
        feed.isArchived = false
        feed.archiveReason = nil
        try? context.save()
    }

    private func unsubscribe(_ feed: RSSFeed) {
        let feedID = feed.id
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.feedID == feedID }
        )
        if let articles = try? context.fetch(descriptor) {
            articles.forEach { context.delete($0) }
        }
        context.delete(feed)
        try? context.save()
    }

    private func addFromURL() async {
        let raw = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = FeedURLNormaliser.normalise(raw), url.scheme?.hasPrefix("http") == true else {
            addError = "Not a valid feed URL."
            return
        }

        isFetching = true
        addError = nil

        let customName = customFeedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = await resolveFeedMetadata(from: url)

        let title: String
        if customName.isEmpty {
            title = metadata.title ?? url.host ?? raw
        } else {
            title = customName
        }
        let category = await autoCategory(for: url, title: title, preview: metadata.preview)

        await MainActor.run {
            subscribe(url: url.absoluteString, title: title, category: category)
            isFetching = false
            customFeedName = ""
            detectedCategoryPreview = nil
            showAddByURL = false
        }
    }

    private func resolveFeedMetadata(from url: URL) async -> (title: String?, preview: String) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        guard let (data, _) = try? await URLSession(configuration: config).data(from: url) else {
            return (nil, "")
        }
        let preview = String(data: data.prefix(6000), encoding: .utf8) ?? ""
        if let title = firstTitle(in: preview), !title.isEmpty {
            return (title, preview)
        }
        return (nil, preview)
    }

    private func firstTitle(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let titleRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let raw = String(text[titleRange])
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.lowercased() != "rss" else { return nil }
        return raw
    }

    private func autoCategory(for url: URL, title: String, preview: String) async -> String {
        let allowed = Self.feedCategoryOptions
        if #available(iOS 26, *), IntelligenceService.isAvailable {
            if let category = await IntelligenceService.classifyFeedCategory(
                feedURL: url.absoluteString,
                feedTitle: title,
                feedPreview: preview,
                allowedCategories: allowed
            ) {
                await MainActor.run { detectedCategoryPreview = category }
                return category
            }
        }

        let fallback = heuristicCategory(
            for: title,
            urlString: url.absoluteString,
            preview: preview,
            allowed: allowed
        )
        await MainActor.run { detectedCategoryPreview = fallback }
        return fallback
    }

    private func heuristicCategory(for title: String, urlString: String, preview: String, allowed: [String]) -> String {
        let haystack = "\(title) \(urlString) \(preview.prefix(1000))".lowercased()
        let preferredByKeyword: [(String, [String])] = [
            ("Technology", ["tech", "developer", "programming", "startup", "software", "ai"]),
            ("Business", ["business", "finance", "economy", "market", "invest"]),
            ("Science", ["science", "research", "physics", "biology", "space", "nature"]),
            ("World News", ["world", "international", "global"]),
            ("News", ["news", "politics", "policy"]),
            ("Design", ["design", "ux", "ui", "product design"]),
            ("Culture", ["culture", "art", "media", "film", "music"]),
            ("Health", ["health", "medical", "wellness"]),
            ("Sports", ["sports", "football", "soccer", "basketball"])
        ]

        for (preferredCategory, keywords) in preferredByKeyword {
            guard let match = allowed.first(where: { $0.caseInsensitiveCompare(preferredCategory) == .orderedSame }) else {
                continue
            }
            if keywords.contains(where: { haystack.contains($0) }) {
                return match
            }
        }

        return allowed.first(where: { $0.caseInsensitiveCompare("General") == .orderedSame })
            ?? allowed.first
            ?? "General"
    }
}

// MARK: - Feed row

private struct FeedRow: View {
    let feed: RSSFeed
    @Query private var articles: [RSSArticle]
    @Environment(\.appTheme) private var appTheme

    init(feed: RSSFeed) {
        self.feed = feed
        let feedID = feed.id
        _articles = Query(filter: #Predicate<RSSArticle> {
            $0.feedID == feedID && !$0.isQueued
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            FaviconView(domain: domain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(feed.title)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(feed.isPaused ? appTheme.textFaint : appTheme.heading)
                        .lineLimit(1)

                    if feed.isPaused {
                        Text("PAUSED")
                            .font(AppTheme.sansSerif(10, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(1.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appTheme.surface)
                            .clipShape(Capsule())
                    } else if feed.feedType == .scraped {
                        Text("WEB")
                            .font(AppTheme.sansSerif(10, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(1.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appTheme.separator)
                            .clipShape(Capsule())
                    } else if feed.feedType == .newsletter {
                        Text("NEWSLETTER")
                            .font(AppTheme.sansSerif(10, weight: .medium))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(1.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appTheme.separator)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(feed.category)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)

                    Text("·")
                        .foregroundStyle(appTheme.textFaint)

                    if let fetched = feed.lastFetchedAt {
                        Text(fetched.formatted(.relative(presentation: .named)))
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    } else {
                        Text(feed.feedType == .newsletter ? "Waiting for first edition." : "Never fetched.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    }
                }
            }

            Spacer()

            if articles.count > 0 {
                Text("\(articles.count)")
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(appTheme.background)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(appTheme.accent)
                    .clipShape(Circle())
            }
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var domain: String {
        guard let url = URL(string: feed.url) else { return feed.url }
        return ContentFetcher.extractDomain(from: url)
    }
}

// MARK: - Archived feed row

private struct ArchivedFeedRow: View {
    let feed: RSSFeed
    let onRestore: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var reasonLabel: String {
        guard let reason = feed.archiveReason else { return "archived" }
        if reason == "manual" { return "manually archived" }
        let parts = reason.split(separator: ":").map(String.init)
        guard parts.count == 2, let days = Int(parts[1]) else { return reason }
        switch parts[0] {
        case "unread": return "not read · \(days)d"
        case "dead":   return "no new articles · \(days)d"
        default:       return reason
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title)
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .lineLimit(1)
                Text(reasonLabel)
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint.opacity(0.6))
            }

            Spacer()

            Button("Restore", action: onRestore)
                .font(AppTheme.sansSerif(13, weight: .medium))
                .foregroundStyle(appTheme.accent)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
