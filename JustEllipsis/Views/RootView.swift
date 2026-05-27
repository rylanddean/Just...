import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @Environment(HealthKitService.self) private var healthKit
    @AppStorage("activityRings.enabled") private var activityRingsEnabled: Bool = false
    @AppStorage("hasCompletedOnboarding")  private var hasCompletedOnboarding: Bool = false

    @State private var hasRunInitialStartupWork = false
    @State private var lastStartupWorkAt: Date = .distantPast

    @AppStorage(ReaderTheme.defaultsKey)         private var themeRaw:         String = "ember"
    @AppStorage(NightModeService.startHourKey)   private var nightStartHour:   Int    = NightModeService.defaultStartHour
    @AppStorage(NightModeService.startMinuteKey) private var nightStartMinute: Int    = NightModeService.defaultStartMinute
    @AppStorage(NightModeService.overrideKey)    private var nightOverride:    String = "auto"

    private var activeTheme: AppTheme {
        let base    = ReaderTheme(rawValue: themeRaw) ?? .ember
        let isNight = NightModeService.isActive(hour: nightStartHour, minute: nightStartMinute, override: nightOverride)
        return AppTheme(theme: isNight ? .night : base)
    }

    var body: some View {
        @Bindable var router = router

        if !hasCompletedOnboarding {
            OnboardingView {
                hasCompletedOnboarding = true
                runStartupWorkIfNeeded(force: true)
            }
            .environment(\.appTheme, activeTheme)
        } else {
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tag(0)
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            FeedsView()
                .tag(1)
                .tabItem {
                    Label("Feeds", systemImage: "dot.radiowaves.left.and.right")
                }

            DigestView()
                .tag(2)
                .tabItem {
                    Label("Digest", systemImage: "newspaper")
                }

            BrainView()
                .tag(3)
                .tabItem {
                    Label("Brain", systemImage: "brain.head.profile")
                }
        }
        .tint(activeTheme.accent)
        .preferredColorScheme(activeTheme.colorScheme)
        .environment(\.appTheme, activeTheme)
        .task {
            guard !hasRunInitialStartupWork else { return }
            hasRunInitialStartupWork = true
            runStartupWorkIfNeeded(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runStartupWorkIfNeeded(force: false)
            } else {
                gradingTracker.reset()
            }
        }
        } // else hasCompletedOnboarding
    }

    // MARK: - Share Extension handoff

    private func processPendingLinks() {
        let urls = PendingLinkStore.drain()
        guard !urls.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<QueuedLink>())) ?? []
        let existingURLs = Set(existing.map { $0.url })
        let maxOrder = existing.map { $0.sortOrder }.max() ?? -1

        var added = 0
        for urlString in urls {
            guard !existingURLs.contains(urlString) else { continue }
            let link = QueuedLink(url: urlString, sortOrder: maxOrder + 1 + added)
            context.insert(link)
            added += 1
        }
        if added > 0 { try? context.save() }
    }

    private func runStartupWorkIfNeeded(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastStartupWorkAt) < 3 { return }
        lastStartupWorkAt = now
        processPendingLinks()
        RSSFetchService.fetchInProcess(container: context.container, tracker: gradingTracker)
        PrefetchService.prefetchInProcess(container: context.container)
        if activityRingsEnabled {
            Task { await healthKit.fetchTodaySummary() }
        }
    }
}
