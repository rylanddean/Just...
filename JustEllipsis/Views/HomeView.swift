import SwiftUI
import SwiftData
import UserNotifications

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \QueuedLink.sortOrder) private var queue: [QueuedLink]
    @Query private var readingDays: [ReadingDay]
    @Query private var feeds: [RSSFeed]
    // Only used to check count < 5 — cap at 5 to avoid loading the full Brain.
    @Query(HomeView.brainEntriesDescriptor) private var brainEntries: [BrainEntry]
    private static let brainEntriesDescriptor: FetchDescriptor<BrainEntry> = {
        var d = FetchDescriptor<BrainEntry>()
        d.fetchLimit = 5
        return d
    }()
    @Query(sort: \DailyEdition.date, order: .reverse) private var editions: [DailyEdition]

    @AppStorage("streak.minReadsPerDay")                  private var minReadsPerDay:       Int  = 1
    @AppStorage("activityRings.enabled")                 private var activityRingsEnabled: Bool = false
    @AppStorage("notifications.permissionOffered")       private var permissionOffered:    Bool = false

    @Environment(HealthKitService.self) private var healthKit

    @State private var showAddLink: Bool = false
    @State private var showSettings: Bool = false
    @State private var activeLink: QueuedLink?
    @State private var safariURL: URL?
    @State private var substackLink: QueuedLink?
    @State private var pendingSubstackEntry: BrainEntry?
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingEdition: DailyEdition?

    private var streak: Int { StreakEngine.calculateStreak(from: readingDays, minReads: minReadsPerDay).current }
    private var isAtRisk: Bool { StreakEngine.isStreakAtRisk(days: readingDays, minReads: minReadsPerDay) }
    private var recentActivity: [Bool] { StreakEngine.recentActivity(days: readingDays, count: 7, minReads: minReadsPerDay) }
    private var hasReadToday: Bool { StreakEngine.hasReadToday(days: readingDays, minReads: minReadsPerDay) }

    private var showActivityCard: Bool {
        activityRingsEnabled
            && HealthKitService.isAvailable
            && healthKit.summary != nil
            && StreakEngine.hasReadToday(days: readingDays, minReads: minReadsPerDay)
    }

    private var picks: [QueuedLink] { queue.filter { $0.source == .aiPick } }
    private var manual: [QueuedLink] { queue.filter { $0.source != .aiPick } }
    private var todaysEdition: DailyEdition? { editions.first { Calendar.current.isDateInToday($0.date) } }

    private var avgAgeDays: Double? {
        guard !queue.isEmpty else { return nil }
        let total = queue.reduce(0.0) { $0 + Date().timeIntervalSince($1.addedAt) }
        return total / Double(queue.count) / 86400
    }

    private var staleLinks: [QueuedLink] {
        let cutoff = Date().addingTimeInterval(-2 * 86400)
        return queue.filter { $0.addedAt < cutoff }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if queue.isEmpty && todaysEdition == nil {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        StreakHeader(streak: streak, isAtRisk: isAtRisk, recentActivity: recentActivity)

                        queueMetaBar

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

                            // Daily Edition card
                            if let edition = todaysEdition {
                                Section {
                                    DailyEditionCard(edition: edition) {
                                        showingEdition = edition
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(
                                        top: 5,
                                        leading: AppTheme.pagePadding,
                                        bottom: 5,
                                        trailing: AppTheme.pagePadding
                                    ))
                                } header: {
                                    editionHeader
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
            .safeAreaInset(edge: .bottom) {
                if showPermissionBanner {
                    permissionBanner
                }
            }
            .task {
                notificationAuthStatus = await NotificationScheduler.authorizationStatus()
            }
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $activeLink) { link in
            ReaderView(source: .queued(link))
        }
        .fullScreenCover(item: $showingEdition) { edition in
            DailyEditionView(edition: edition)
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
                ReflectView(entry: entry, onComplete: {
                    markSubstackRead(link)
                    substackLink = nil
                })
            }
        }
    }

    // MARK: - Permission Banner

    private var showPermissionBanner: Bool {
        streak >= 3 && !permissionOffered && notificationAuthStatus == .notDetermined
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Text("Enable reminders to protect your streak?")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Enable") {
                permissionOffered = true
                Task {
                    _ = await NotificationScheduler.requestPermission()
                    notificationAuthStatus = await NotificationScheduler.authorizationStatus()
                }
            }
            .font(AppTheme.sansSerif(13, weight: .semibold))
            .foregroundStyle(appTheme.accent)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
        .background(appTheme.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(appTheme.separator), alignment: .top)
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

    // MARK: - Edition header

    private var editionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "newspaper")
                .font(.system(size: 10))
                .foregroundStyle(appTheme.accent)

            Text("DAILY EDITION")
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

    // MARK: - Queue meta bar

    private var queueMetaBar: some View {
        HStack(alignment: .center, spacing: 0) {
            if let avg = avgAgeDays, avg >= 1 {
                let days = Int(avg.rounded())
                Text("avg. \(days) day\(days == 1 ? "" : "s") old")
                    .font(AppTheme.mono(12))
                    .foregroundStyle(avg >= 3 ? appTheme.accent.opacity(0.8) : appTheme.textFaint)
            }

            Spacer()

            if !staleLinks.isEmpty {
                Button {
                    cleanupQueue()
                } label: {
                    Text("Clean up queue")
                        .font(AppTheme.sansSerif(12, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func cleanupQueue() {
        let cutoff = Date().addingTimeInterval(-2 * 86400)
        for link in staleLinks where link.addedAt < cutoff {
            let url = link.url
            let descriptor = FetchDescriptor<RSSArticle>(predicate: #Predicate { $0.url == url })
            if let article = try? context.fetch(descriptor).first {
                article.isQueued = false
            }
            context.delete(link)
        }
        try? context.save()
    }

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

            if hasReadToday {
                VStack(spacing: 8) {
                    Text("Nothing saved for later.")
                        .font(AppTheme.sansSerif(18, weight: .medium))
                        .foregroundStyle(appTheme.heading)

                    Text("You read today.")
                        .font(AppTheme.mono(13))
                        .foregroundStyle(appTheme.textFaint)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Nothing to read.")
                        .font(AppTheme.sansSerif(18, weight: .medium))
                        .foregroundStyle(appTheme.heading)

                    Text(feeds.isEmpty ? "Add a link to start reading." : "Add a link or wait for your picks.")
                        .font(AppTheme.sansSerif(14))
                        .foregroundStyle(appTheme.textFaint)
                }
            }

            Spacer()

            if !hasReadToday {
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
}
