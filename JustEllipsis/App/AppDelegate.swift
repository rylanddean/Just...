import UIKit
import CloudKit
import os.log

private let delegateLog = Logger(
    subsystem: "com.rylandean.justellipsis",
    category: "AppDelegate"
)

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        delegateLog.info("APNs registered (token: \(deviceToken.map { String(format: "%02x", $0) }.joined()))")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        delegateLog.error("APNs registration failed: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard
            let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
            notification.subscriptionID == MacLinkSubscriptionService.subscriptionID
        else {
            completionHandler(.noData)
            return
        }

        delegateLog.info("CloudKit push received — promoting pending Mac links")

        guard let container = JustEllipsisApp.sharedContainer else {
            delegateLog.error("sharedContainer not set — skipping promotion")
            completionHandler(.failed)
            return
        }

        Task {
            let receiver = MacLinkReceiver(modelContainer: container)
            await receiver.checkAndPromoteAsync()
            completionHandler(.newData)
        }
    }
}
