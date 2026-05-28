import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \QueuedLink.sortOrder) private var queue: [QueuedLink]
    @Query private var readingDays: [ReadingDay]
    @Query private var feeds: [RSSFeed]
    @Query private var brainEntries: [BrainEntry]

    @AppStorage("streak.minReadsPerDay")   private var minReadsPerDay:       Int  = 1
    @AppStorage("activityRings.enabled")  private var activityRingsEnabled: Bool = false

    @Environment(HealthKitService.self) private var healthKit

    @State private var showAddLink: Bool = false
    @State private var showSettings: Bool = false
    @State private var activeLink: QueuedLink?
    @State private var safariURL: URL?
    @State private var substackLink: QueuedLink?
    @State private var pendingSubstackEntry: BrainEntry?

    private var streak: Int { StreakEngine.calculateStreak(from: readingDays, minReads: minReadsPerDay).current }
    private var isAtRisk: Bool { StreakEngine.isStreakAtRisk(days: readingDays, minReads: minReadsPerDay) }
    private var recentActivity: [Bool] { StreakEngine.recentActivity(days: readingDays, count: 7, minReads: minReadsPerDay) }

    private var showActivityCard: Bool {
        activityRingsEnabled
            && HealthKitService.isAvailable
            && healthKit.summary != nil
            && StreakEngine.hasReadToday(days: readingDays, minReads: minReadsPerDay)
    }

    private var picks: [QueuedLink] { queue.filter { $0.source == .aiPick } }
    private var manual: [QueuedLink] { queue.filter { $0.source != .aiPick } }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if queue.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        StreakHeader(streak: streak, isAtRisk: isAtRisk, recentActivity: recentActivity)

                        List {
                            // Activity rings card — shown after daily goal is met
                            if showActivityCard, let summary = healthKit.summary {
                                Section {
                                    ActivityRingsCard(summary: summary)
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
                            }

                            // Picked for you section
                            if !picks.isEmpty {
                                Section {
                                    if !feeds.isEmpty && brainEntries.count < 5 {
                                        Text("Read more to improve your picks.")
                                            .font(AppTheme.sansSerif(12))
                                            .foregroundStyle(appTheme.textFaint)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(
                                                top: 0,
                                                leading: AppTheme.pagePadding,
                                                bottom: 4,
                                                trailing: AppTheme.pagePadding
                                            ))
                                    }

                                    ForEach(picks) { link in
                                        LinkCard(link: link) {
                                            open(link)
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
                                                deleteLink(link)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                            .tint(AppTheme.danger)
                                        }
                                    }
                                } header: {
                                    picksHeader
                                }
                                .listSectionSeparator(.hidden)
                            }

                            // Manual queue
                            ForEach(manual) { link in
                                LinkCard(link: link) {
                                    open(link)
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
                                        deleteLink(link)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(AppTheme.danger)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .contentMargins(.bottom, 32, for: .scrollContent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Just…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(appTheme.accent)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddLink = true
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
        .sheet(isPresented: $showAddLink) {
            AddLinkView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $activeLink) { link in
            ReaderView(link: link)
        }
        .sheet(item: $safariURL, onDismiss: {
            guard let link = substackLink else { return }
            let parsedURL = URL(string: link.url)
            let title = link.title ?? parsedURL.map { ContentFetcher.extractDomain(from: $0) } ?? link.url
            let domain = link.domain ?? parsedURL.map { ContentFetcher.extractDomain(from: $0) } ?? link.url
            let entry = BrainEntry(url: link.url, title: title, domain: domain)
            pendingSubstackEntry = entry
        }) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .sheet(item: $pendingSubstackEntry) { entry in
            if let link = substackLink {
                ReflectView(entry: entry, link: link, onComplete: {
                    markSubstackRead(link)
                    substackLink = nil
                })
            }
        }
    }

    private func open(_ link: QueuedLink) {
        if let url = URL(string: link.url),
           let host = url.host,
           host.hasSuffix(".substack.com"),
           url.pathComponents.dropFirst().first == "p" {
            substackLink = link
            safariURL = url
        } else {
            activeLink = link
        }
    }

    private func markSubstackRead(_ link: QueuedLink) {
        let url = link.url
        let articleDescriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.url == url }
        )
        if let article = try? context.fetch(articleDescriptor).first {
            article.isQueued = false
            let feedID = article.feedID
            let feedDescriptor = FetchDescriptor<RSSFeed>(predicate: #Predicate { $0.id == feedID })
            if let feed = try? context.fetch(feedDescriptor).first {
                feed.lastReadAt = Date()
            }
        }
        context.delete(link)

        let logical = StreakEngine.logicalDay()
        let y = logical.year, m = logical.month, d = logical.day
        let dayDescriptor = FetchDescriptor<ReadingDay>(
            predicate: #Predicate { $0.year == y && $0.month == m && $0.day == d }
        )
        if let existing = try? context.fetch(dayDescriptor).first {
            existing.linksRead += 1
        } else {
            let day = ReadingDay(year: y, month: m, day: d)
            day.linksRead = 1
            context.insert(day)
        }
        try? context.save()
    }

    // MARK: - Picks header

    private var picksHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(appTheme.accent)

            Text("FROM YOUR FEEDS")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.accent)
                .kerning(2)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .background(appTheme.background)
    }

    // MARK: - Actions

    private func deleteLink(_ link: QueuedLink) {
        let url = link.url
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.url == url }
        )
        if let article = try? context.fetch(descriptor).first {
            article.isQueued = false
        }
        context.delete(link)
        try? context.save()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            StreakHeader(streak: streak, isAtRisk: isAtRisk, recentActivity: recentActivity)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                Text("Nothing to read.")
                    .font(AppTheme.sansSerif(18, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text(feeds.isEmpty ? "Add a link to start reading." : "Add a link or wait for your picks.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
            }

            Spacer()

            Button {
                showAddLink = true
            } label: {
                HStack {
                    Spacer()
                    Text("Add a link")
                        .font(AppTheme.sansSerif(15, weight: .semibold))
                        .foregroundStyle(appTheme.background)
                    Spacer()
                }
                .frame(height: 48)
                .background(appTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 32)
        }
    }
}
