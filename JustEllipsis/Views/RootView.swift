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
    @State private var showFirstLinkPrompt = false

    @AppStorage(ReaderTheme.defaultsKey)         private var themeRaw:         String = "ember"
    @AppStorage(NightModeService.startHourKey)   private var nightStartHour:   Int    = NightModeService.defaultStartHour
    @AppStorage(NightModeService.startMinuteKey) private var nightStartMinute: Int    = NightModeService.defaultStartMinute
    @AppStorage(NightModeService.overrideKey)    private var nightOverride:    String = "auto"

    @State private var activeTheme: AppTheme = AppTheme()

    @AppStorage("streak.minReadsPerDay")                   private var minReadsPerDay:   Int  = 1
    @AppStorage(NotificationScheduler.morningEnabledKey)   private var morningEnabled:   Bool = false
    @AppStorage(NotificationScheduler.morningHourKey)      private var morningHour:      Int  = NotificationScheduler.defaultMorningHour
    @AppStorage(NotificationScheduler.morningMinuteKey)    private var morningMinute:    Int  = NotificationScheduler.defaultMorningMinute
    @AppStorage(NotificationScheduler.eveningEnabledKey)   private var eveningEnabled:   Bool = false
    @AppStorage(NotificationScheduler.eveningHourKey)      private var eveningHour:      Int  = NotificationScheduler.defaultEveningHour
    @AppStorage(NotificationScheduler.eveningMinuteKey)    private var eveningMinute:    Int  = NotificationScheduler.defaultEveningMinute

    @Query(sort: \QueuedLink.sortOrder) private var queue: [QueuedLink]
    @Query private var readingDays: [ReadingDay]

    private func computeTheme() -> AppTheme {
        let base    = ReaderTheme(rawValue: themeRaw) ?? .ember
        let isNight = NightModeService.isActive(hour: nightStartHour, minute: nightStartMinute, override: nightOverride)
        return AppTheme(theme: isNight ? .night : base)
    }

    var body: some View {
        @Bindable var router = router

        if !hasCompletedOnboarding {
            OnboardingView { seededFeeds in
                hasCompletedOnboarding = true
                runStartupWorkIfNeeded(force: true)
                // Only nudge the user to add their own link when onboarding
                // didn't already seed any feeds. Wait for the view swap.
                if !seededFeeds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showFirstLinkPrompt = true
                    }
                }
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
        .sheet(isPresented: $showFirstLinkPrompt) {
            AddLinkView()
                .environment(\.appTheme, activeTheme)
        }
        .task {
            activeTheme = computeTheme()
            guard !hasRunInitialStartupWork else { return }
            hasRunInitialStartupWork = true
            runStartupWorkIfNeeded(force: true)
        }
        .onChange(of: themeRaw)       { _, _ in activeTheme = computeTheme() }
        .onChange(of: nightStartHour) { _, _ in activeTheme = computeTheme() }
        .onChange(of: nightStartMinute) { _, _ in activeTheme = computeTheme() }
        .onChange(of: nightOverride)  { _, _ in activeTheme = computeTheme() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activeTheme = computeTheme()
                runStartupWorkIfNeeded(force: false)
            } else {
                gradingTracker.reset()
            }
        }
        } // else hasCompletedOnboarding
    }

    // MARK: - Share Extension handoff

    // Drains any UserDefaults fallback entries left by the share extension when
    // the direct SwiftData write failed (e.g. fresh install). The common case
    // (direct write succeeded) is a no-op here since PendingLinkStore is empty.
    private func processPendingLinks() {
        let actor = LinkPromotionActor(modelContainer: context.container)
        Task { await actor.promotePendingLinks() }
    }

    // Promotes any JE_PendingLink records written by the Mac Safari extension.
    // No-op when iCloud is unavailable or there are no pending records.
    private func checkMacPendingLinks() {
        let receiver = MacLinkReceiver(modelContainer: context.container)
        receiver.checkAndPromote()
    }

    private func runStartupWorkIfNeeded(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastStartupWorkAt) < 3 { return }
        lastStartupWorkAt = now
        processPendingLinks()
        checkMacPendingLinks()
        MacLinkSubscriptionService.ensureSubscribed()
        PrefetchService.prefetchInProcess(container: context.container)
        if activityRingsEnabled {
            Task { await healthKit.fetchTodaySummary() }
        }
        NotificationScheduler.reschedule(
            queueCount: queue.count,
            readingDays: readingDays,
            minReads: minReadsPerDay,
            morningEnabled: morningEnabled,
            morningHour: morningHour,
            morningMinute: morningMinute,
            eveningEnabled: eveningEnabled,
            eveningHour: eveningHour,
            eveningMinute: eveningMinute
        )
    }
}
