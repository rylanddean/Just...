import SwiftUI

@main
struct JustEllipsisMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Accessory apps must declare at least one scene. Settings{} satisfies
        // that requirement without showing any window to the user.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no menu bar entry — this app exists solely as the
        // required container for the Safari Web Extension. All CloudKit writes
        // happen inside the extension process via SafariWebExtensionHandler.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
