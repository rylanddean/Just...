import SwiftData
import Foundation

@Model
final class BrainEntry {
    var id: UUID = UUID()
    var url: String = ""
    var title: String = ""
    var domain: String = ""
    var readAt: Date = Date()
    var reflection: String?
    var reflectionMode: String?   // "typed" | "voice" | nil
    var reflectionSeconds: Int = 0
    var wordCount: Int = 0
    var aiSummary: String?
    var dna: String?

    init(url: String, title: String, domain: String) {
        self.url = url
        self.title = title
        self.domain = domain
    }
}
