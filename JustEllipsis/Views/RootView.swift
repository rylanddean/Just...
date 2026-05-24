import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            BrainView()
                .tabItem {
                    Label("Brain", systemImage: "brain.head.profile")
                }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .task { processPendingLinks() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { processPendingLinks() }
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
