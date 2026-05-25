import Foundation

enum FeedType: String, Codable {
    case article
    case podcast
}

enum TranscriptFormat: String, Codable {
    case vtt  = "text/vtt"
    case srt  = "application/x-subrip"
    case json = "application/json"
    case html = "text/html"

    static func from(_ mimeType: String) -> TranscriptFormat? {
        let lower = mimeType.lowercased().trimmingCharacters(in: .whitespaces)
        return TranscriptFormat(rawValue: lower)
            ?? (lower.contains("vtt") ? .vtt : nil)
            ?? (lower.contains("subrip") || lower.contains("srt") ? .srt : nil)
            ?? (lower.contains("json") ? .json : nil)
            ?? (lower.contains("html") ? .html : nil)
    }
}

enum TranscriptState: String {
    case unavailable
    case generating
    case ready
}
