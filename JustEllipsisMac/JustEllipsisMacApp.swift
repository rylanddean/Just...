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
    private let server = LocalLinkServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon, no menu bar entry — the companion exists solely to host
        // the Safari extension and appears only in Safari → Settings → Extensions.
        NSApplication.shared.setActivationPolicy(.accessory)
        server.start()
    }
}
