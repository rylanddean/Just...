import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct JustEllipsisApp: App {

    let container: ModelContainer = makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
        .backgroundTask(.appRefresh(PrefetchService.backgroundTaskID)) {
            let actor = PrefetchActor(modelContainer: container)
            await actor.prefetch(max: 3)
            PrefetchService.scheduleNextBackgroundTask()
        }
    }

    // MARK: - ModelContainer

    static let iCloudSyncKey = "iCloudSyncEnabled"

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([QueuedLink.self, BrainEntry.self, ReadingDay.self])
        let syncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncKey)
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let cloudDB: ModelConfiguration.CloudKitDatabase = (syncEnabled && iCloudAvailable)
            ? .private("iCloud.com.rylandean.justellipsis")
            : .none

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PendingLinkStore.appGroupID
        ) {
            let storeURL = groupURL.appendingPathComponent("JustEllipsis.store")
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: cloudDB)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
