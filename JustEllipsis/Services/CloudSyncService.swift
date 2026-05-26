import Foundation

// Handles the two manual sync operations exposed in Settings.
//
// Force Upload: caller saves the ModelContext, then observes
//   NSPersistentCloudKitContainer.eventChangedNotification for an export event.
//   No file operations needed — NSPersistentCloudKitContainer pushes the saved
//   changes automatically.
//
// Force Restore: schedules a local-store deletion that makeContainer() applies
//   on the NEXT launch, before the persistent store is opened. CloudKit then
//   performs a full download into the fresh store.

enum CloudSyncService {
    static let pendingRestoreKey = "pendingCloudRestore"
    private static let iCloudSyncKey = "iCloudSyncEnabled"

    // Marks a restore pending. Executed by makeContainer() on next launch.
    static func scheduleRestore() {
        UserDefaults.standard.set(true, forKey: pendingRestoreKey)
    }

    // Called by makeContainer() before the persistent store is created.
    // Deletes the SQLite store files so SwiftData starts fresh and CloudKit
    // re-downloads all records. No-op if sync is disabled or iCloud is unavailable.
    static func applyPendingRestoreIfNeeded(storeURL: URL) {
        guard UserDefaults.standard.bool(forKey: pendingRestoreKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)

        let syncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncKey)
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        guard syncEnabled && iCloudAvailable else { return }

        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
    }
}
