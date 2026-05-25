import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
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
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            processPendingLinks()
            RSSFetchService.fetchInProcess(container: context.container)
            PrefetchService.prefetchInProcess(container: context.container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                processPendingLinks()
                RSSFetchService.fetchInProcess(container: context.container)
                PrefetchService.prefetchInProcess(container: context.container)
            }
        }
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
}
