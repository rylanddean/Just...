import SwiftUI
import SwiftData

struct FeedsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \RSSFeed.title) private var feeds: [RSSFeed]

    @State private var showAddByURL = false
    @State private var showDirectory = false
    @State private var pasteURL = ""
    @State private var customFeedName = ""
    @State private var addError: String?
    @State private var isFetching = false
    @State private var feedToRename: RSSFeed?
    @State private var renameText = ""
    @State private var showRenameSheet = false


    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if feeds.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .navigationTitle("Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDirectory = true
                    } label: {
                        Text("Browse")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pasteURL = ""
                        customFeedName = ""
                        addError = nil
                        showAddByURL = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showAddByURL) {
            addByURLSheet
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        unsubscribe(feed)
                    } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                    .tint(AppTheme.danger)
                }
                .contextMenu {
                    Button {
                        renameText = feed.title
                        feedToRename = feed
                        showRenameSheet = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
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
                    .foregroundStyle(AppTheme.heading)

                Text("Browse feeds or add a URL.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(AppTheme.textFaint)
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
                            .foregroundStyle(AppTheme.background)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    pasteURL = ""
                    customFeedName = ""
                    addError = nil
                    showAddByURL = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Add a URL")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.textFaint)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.separator, lineWidth: 1)
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
                AppTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FEED URL")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(AppTheme.textFaint)
                            .kerning(2)

                        TextField("https://example.com/feed.xml", text: $pasteURL)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.heading)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .padding(AppTheme.cardPadding)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM NAME (OPTIONAL)")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(AppTheme.textFaint)
                            .kerning(2)

                        TextField("Leave blank to use the feed's title", text: $customFeedName)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.heading)
                            .padding(AppTheme.cardPadding)
                            .background(AppTheme.surface)
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
                                    .tint(AppTheme.background)
                            } else {
                                Text("Add feed")
                                    .font(AppTheme.sansSerif(15, weight: .semibold))
                                    .foregroundStyle(AppTheme.background)
                            }
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(pasteURL.isEmpty ? AppTheme.accentFaint : AppTheme.accent)
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
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Rename sheet

    private var renameSheet: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FEED NAME")
                            .font(AppTheme.sansSerif(11, weight: .medium))
                            .foregroundStyle(AppTheme.textFaint)
                            .kerning(2)

                        TextField("Feed name", text: $renameText)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.heading)
                            .padding(AppTheme.cardPadding)
                            .background(AppTheme.surface)
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
                                .foregroundStyle(AppTheme.background)
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(trimmed.isEmpty ? AppTheme.accentFaint : AppTheme.accent)
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
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func subscribe(url: String, title: String, category: String) {
        guard !feeds.contains(where: { $0.url == url }) else { return }
        let feed = RSSFeed(url: url, title: title, category: category)
        context.insert(feed)
        try? context.save()
        RSSFetchService.fetchInProcess(container: context.container)
    }

    private func unsubscribe(_ feed: RSSFeed) {
        context.delete(feed)
        try? context.save()
    }

    private func addFromURL() async {
        let raw = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else {
            addError = "Not a valid feed URL."
            return
        }

        isFetching = true
        addError = nil

        let customName = customFeedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if customName.isEmpty {
            title = await resolveTitle(from: url) ?? url.host ?? raw
        } else {
            title = customName
        }

        await MainActor.run {
            subscribe(url: raw, title: title, category: "Custom")
            isFetching = false
            customFeedName = ""
            showAddByURL = false
        }
    }

    private func resolveTitle(from url: URL) async -> String? {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        guard let (data, _) = try? await URLSession(configuration: config).data(from: url) else {
            return nil
        }
        let preview = String(data: data.prefix(2048), encoding: .utf8) ?? ""
        if let range = preview.range(of: "<title>"),
           let endRange = preview.range(of: "</title>", range: range.upperBound..<preview.endIndex) {
            let raw = String(preview[range.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { return raw }
        }
        return nil
    }
}

// MARK: - Feed row

private struct FeedRow: View {
    let feed: RSSFeed
    @Query private var articles: [RSSArticle]

    init(feed: RSSFeed) {
        self.feed = feed
        let feedID = feed.id
        _articles = Query(filter: #Predicate<RSSArticle> {
            $0.feedID == feedID && !$0.isQueued
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(feed.title)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(feed.isPaused ? AppTheme.textFaint : AppTheme.heading)
                        .lineLimit(1)

                    if feed.isPaused {
                        Text("PAUSED")
                            .font(AppTheme.sansSerif(10, weight: .medium))
                            .foregroundStyle(AppTheme.textFaint)
                            .kerning(1.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(feed.category)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(AppTheme.textFaint)

                    Text("·")
                        .foregroundStyle(AppTheme.textFaint)

                    if let fetched = feed.lastFetchedAt {
                        Text(fetched, style: .relative)
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.textFaint)
                    } else {
                        Text("Never fetched.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.textFaint)
                    }
                }
            }

            Spacer()

            if articles.count > 0 {
                Text("\(articles.count)")
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(AppTheme.background)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(AppTheme.readerAccent)
                    .clipShape(Circle())
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
