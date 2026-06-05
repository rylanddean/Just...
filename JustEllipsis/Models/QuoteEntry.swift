import SwiftData
import Foundation

@Model
final class QuoteEntry {
    var id: UUID = UUID()
    var text: String = ""
    var url: String = ""
    var title: String = ""
    var domain: String = ""
    var savedAt: Date = Date()

    init(text: String, url: String, title: String, domain: String) {
        self.text = text
        self.url = url
        self.title = title
        self.domain = domain
    }
}
