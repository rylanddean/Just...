import Foundation
import Observation

@Observable
final class AppRouter {
    var selectedTab: Int = 0
    // Set by onOpenURL; FeedsView drains this to pre-fill the Add Feed sheet.
    var pendingFeedURL: String?
}
