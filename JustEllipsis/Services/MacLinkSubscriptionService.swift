import CloudKit
import os.log

private let subLog = Logger(
    subsystem: "com.rylandean.justellipsis",
    category: "MacLinkSubscription"
)

enum MacLinkSubscriptionService {

    private static let containerID = "iCloud.com.rylandean.justellipsis"
    static let subscriptionID = "je-pending-link-created"
    private static let registeredKey = "je.cloudkit.maclink.subscribed"

    // Registers a CloudKit query subscription for new JE_PendingLink records so
    // the app receives a silent push the moment the Safari extension saves a link.
    // No-op after the first successful registration (stored in UserDefaults).
    static func ensureSubscribed() {
        guard !UserDefaults.standard.bool(forKey: registeredKey) else { return }
        Task { await register() }
    }

    private static func register() async {
        let container = CKContainer(identifier: containerID)

        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                subLog.info("register: iCloud unavailable (\(String(describing: status)))")
                return
            }
        } catch {
            subLog.error("register: accountStatus error: \(error)")
            return
        }

        let sub = CKQuerySubscription(
            recordType: MacLinkReceiver.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: .firesOnRecordCreation
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        sub.notificationInfo = info

        do {
            _ = try await container.privateCloudDatabase.save(sub)
            UserDefaults.standard.set(true, forKey: registeredKey)
            subLog.info("register: subscription saved")
        } catch {
            subLog.error("register: save failed (will retry next launch): \(error)")
        }
    }
}
