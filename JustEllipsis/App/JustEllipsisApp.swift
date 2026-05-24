import SwiftUI
import SwiftData

@main
struct JustEllipsisApp: App {

    let container: ModelContainer = makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }

    // MARK: - ModelContainer

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([QueuedLink.self, BrainEntry.self, ReadingDay.self])

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PendingLinkStore.appGroupID
        ) {
            let storeURL = groupURL.appendingPathComponent("JustEllipsis.store")
            let config = ModelConfiguration(schema: schema, url: storeURL)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
